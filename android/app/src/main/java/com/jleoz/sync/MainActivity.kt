package com.jleoz.sync

import android.content.Intent
import android.net.Uri
import android.os.Build
import com.jleoz.sync.Services.OauthKeepAliveService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Flutter 宿主 Activity。
 *
 * 原来的 `com.jleoz.sync.Activities.MainActivity` 是纯原生 Activity，
 * 迁移到 Flutter 后必须换成 [FlutterActivity]，否则安装后只会显示旧的原生界面，
 * Dart 代码根本不会被加载。
 *
 * 这里额外承担两件 Dart 做不到的事：
 *  1. 暴露 `nativeLibraryDir` —— engine 可执行文件（`engine.so`）的真实位置；
 *  2. 接收系统分享（`ACTION_SEND` / `ACTION_SEND_MULTIPLE`），把文件复制到
 *     缓存目录后把路径交给 Dart（对应原生 `Activities/SharingActivity.java`）。
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** 冷启动时随启动 Intent 带进来的分享内容，等 Dart 来取。 */
    private var pendingShare: List<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        Privileged.attach(this, methodChannel)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart 侧的 EnginePaths 优先用这个，比解析 resolvedExecutable 更稳。
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)

                // ── 高级权限（Shizuku / Dhizuku / 运行时权限） ──
                "privStatus" -> result.success(Privileged.status(this))
                "shizukuRequestPermission" ->
                    result.success(Privileged.shizukuRequestPermission())
                "dhizukuRequestPermission" ->
                    result.success(Privileged.dhizukuRequestPermission(this))
                "hasAllFiles" -> result.success(Privileged.hasAllFiles(this))
                "openAllFilesSettings" ->
                    result.success(Privileged.openAllFilesSettings(this))
                "requestRuntimePerms" -> {
                    Privileged.requestRuntimePermissions(this)
                    result.success(true)
                }
                "isIgnoringBattery" -> result.success(Privileged.batteryExempt(this))
                "requestBatteryExemption" ->
                    result.success(Privileged.requestBatteryExemption(this))
                "privExec" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?>
                    val source = args?.get("source") as? String ?: "shizuku"
                    val cmd = (args?.get("cmd") as? List<*>)
                        ?.filterIsInstance<String>()
                        ?: emptyList()
                    if (cmd.isEmpty()) {
                        result.success(
                            mapOf("exit" to -1, "out" to "", "err" to "empty command"),
                        )
                    } else {
                        Privileged.exec(this, source, cmd, result)
                    }
                }

                // OAuth 授权期间给引擎子进程保活：应用切到浏览器后进入缓存态，
                // Android 12+ 会杀掉 app exec 出来的子进程，导致回调服务器
                // 跟着死亡、授权永远完不成。前台服务把进程顶在缓存态之上。
                "oauthKeepAliveStart" -> {
                    try {
                        val intent = Intent(this, OauthKeepAliveService::class.java)
                        androidx.core.content.ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    } catch (e: Exception) {
                        // 保活失败不阻塞授权本身，只是成功率下降。
                        android.util.Log.w(TAG, "OAuth 保活服务启动失败", e)
                        result.success(false)
                    }
                }

                "oauthKeepAliveStop" -> {
                    try {
                        val intent = Intent(this, OauthKeepAliveService::class.java)
                            .setAction(OauthKeepAliveService.ACTION_STOP)
                        startService(intent)
                    } catch (e: Exception) {
                        android.util.Log.w(TAG, "OAuth 保活服务停止失败", e)
                    }
                    result.success(true)
                }

                // 冷启动分享：取一次并清空，避免重复处理。
                "takeInitialShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }

                else -> result.notImplemented()
            }
        }

        // 冷启动就带着分享进来的情况：先缓存，Dart 起来后会来取。
        pendingShare = extractSharedPaths(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // 热启动（App 已在后台）直接推给 Dart。
        val paths = extractSharedPaths(intent)
        if (!paths.isNullOrEmpty()) {
            channel?.invokeMethod("onShared", paths)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        Privileged.onRuntimeResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        Privileged.detach()
        super.onDestroy()
    }

    /**
     * 把 `ACTION_SEND` 的内容物化成可用的文件路径。
     *
     * Android 分享过来的是 `content://` URI，engine 不认，所以要复制到
     * 应用缓存目录再交给 Dart。
     */
    private fun extractSharedPaths(intent: Intent?): List<String>? {
        if (intent == null) return null
        val action = intent.action ?: return null
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val uris: List<Uri> = when (action) {
            Intent.ACTION_SEND ->
                listOfNotNull(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    },
                )
            else ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                        ?: emptyList()
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                        ?: emptyList()
                }
        }
        if (uris.isEmpty()) return null

        val outDir = File(cacheDir, "shared").apply { mkdirs() }
        val copied = ArrayList<String>(uris.size)

        for (uri in uris) {
            try {
                val name = queryDisplayName(uri) ?: UUID.randomUUID().toString()
                val target = File(outDir, "${System.currentTimeMillis()}_$name")
                contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                copied.add(target.absolutePath)
            } catch (e: Exception) {
                // 单个文件失败不影响其余的。
                android.util.Log.w(TAG, "复制分享内容失败: $uri", e)
            }
        }
        return copied.ifEmpty { null }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        const val CHANNEL = "com.jleoz.sync/native"
        private const val TAG = "MainActivity"
    }
}
