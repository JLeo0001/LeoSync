package com.jleoz.sync

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.rosan.dhizuku.api.Dhizuku
import com.rosan.dhizuku.api.DhizukuRequestPermissionListener
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import rikka.shizuku.Shizuku
import rikka.sui.Sui
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * 高级权限桥 —— Shizuku / Dhizuku 代授 + 运行时权限一站式处理。
 *
 * ## 为什么要 Shizuku / Dhizuku
 *
 * Android 11+ 的分区存储把 `Android/data`、`Android/obb` 锁死了，普通应用
 * （包括我们的引擎子进程）读不了。两条路：
 *
 *  1. 「所有文件访问」(MANAGE_EXTERNAL_STORAGE)：普通流程只能跳系统设置页让
 *     用户手动开；有 Shizuku（ADB/Root 特权）或 Dhizuku（设备所有者特权）时，
 *     可以直接 `appops set --uid <pkg> MANAGE_EXTERNAL_STORAGE allow`，
 *     一次搞定 —— 引擎子进程（同 UID）随即获得完整存储能力。
 *  2. 顺带把通知、旧版存储等运行时权限也静默授予。
 *
 * ## 实现方式
 *
 *  * **Dhizuku**：`Dhizuku.newProcess`（公开 API，跑在设备所有者身份）。
 *  * **Shizuku**：`Shizuku.newProcess` 在 API 13 里已不是公开接口，因此按官方
 *    推荐改走 **UserService**（[IPrivilegedService] + [PrivilegedService]），
 *    服务进程以 shell 身份常驻，绑定后逐条执行命令。
 *
 * ## 与 Dart 的约定
 *
 * 全部走 `com.jleoz.sync/native` 通道（MainActivity 注册）：
 *
 *  * 同步方法：`privStatus` / `hasAllFiles` / `isIgnoringBattery` /
 *    `openAllFilesSettings` / `requestRuntimePerms` / `requestBatteryExemption` /
 *    `shizukuRequestPermission` / `dhizukuRequestPermission`；
 *  * `privExec(source, cmd)`：source 为 `shizuku` 或 `dhizuku`，结果异步回 Dart；
 *  * 异步事件统一 `onPrivEvent`：`{type, ...}`。
 */
object Privileged {

    private const val REQUEST_CODE_SHIZUKU = 42017
    private const val REQUEST_CODE_RUNTIME = 42018
    private const val USER_SERVICE_VERSION = 1

    private var channel: MethodChannel? = null
    private var suiChecked = false
    private val shizukuListenerInstalled = AtomicBoolean(false)

    /** Shizuku UserService 连接状态。 */
    private var shizukuService: IPrivilegedService? = null
    private val shizukuConnecting = AtomicBoolean(false)

    /** 服务未就绪时暂存的待执行命令。 */
    private val pendingShizuku = mutableListOf<Pair<List<String>, MethodChannel.Result>>()

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── 生命周期 ────────────────────────────────────────────────────────

    /** 在宿主 Activity 配置好引擎后调用一次。 */
    fun attach(activity: Activity, methodChannel: MethodChannel) {
        channel = methodChannel
        if (shizukuListenerInstalled.compareAndSet(false, true)) {
            Shizuku.addRequestPermissionResultListener { requestCode, grantResult ->
                if (requestCode == REQUEST_CODE_SHIZUKU) {
                    emit(
                        "shizukuPermission",
                        mapOf("granted" to (grantResult == PackageManager.PERMISSION_GRANTED)),
                    )
                }
            }
        }
    }

    fun detach() {
        channel = null
    }

    private fun emit(type: String, data: Map<String, Any?>) {
        mainHandler.post {
            channel?.invokeMethod(
                "onPrivEvent",
                mapOf("type" to type, "data" to data),
            )
        }
    }

    // ── 状态 ────────────────────────────────────────────────────────────

    /** 汇总所有权限状态，一次拉全。 */
    fun status(activity: Activity): Map<String, Any?> {
        val sui = try {
            if (!suiChecked) {
                suiChecked = true
                Sui.init(activity.packageName)
            } else {
                true
            }
        } catch (t: Throwable) {
            false
        }

        val shizukuBinder = try {
            Shizuku.pingBinder()
        } catch (t: Throwable) {
            false
        }
        val shizukuGranted = try {
            shizukuBinder && !Shizuku.isPreV11() &&
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (t: Throwable) {
            false
        }

        var dhizukuAvailable = false
        var dhizukuGranted = false
        try {
            dhizukuAvailable = Dhizuku.init(activity)
            if (dhizukuAvailable) {
                dhizukuGranted = Dhizuku.isPermissionGranted()
            }
        } catch (t: Throwable) {
            dhizukuAvailable = false
        }

        return mapOf(
            "packageName" to activity.packageName,
            "sui" to sui,
            "shizukuBinder" to shizukuBinder,
            "shizukuGranted" to shizukuGranted,
            "dhizukuAvailable" to dhizukuAvailable,
            "dhizukuGranted" to dhizukuGranted,
            "allFilesGranted" to hasAllFiles(activity),
            "notifGranted" to notifGranted(activity),
            "legacyStorageGranted" to legacyStorageGranted(activity),
            "batteryExempt" to batteryExempt(activity),
        )
    }

    /** 「所有文件访问」是否已授予（API 30+ 看 appops，更老版本看运行时权限）。 */
    fun hasAllFiles(context: Context): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            legacyStorageGranted(context)
        }
    } catch (t: Throwable) {
        false
    }

    fun notifGranted(context: Context): Boolean = try {
        NotificationManagerCompat.from(context).areNotificationsEnabled()
    } catch (t: Throwable) {
        false
    }

    fun legacyStorageGranted(context: Context): Boolean = try {
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
    } catch (t: Throwable) {
        false
    }

    fun batteryExempt(context: Context): Boolean = try {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.isIgnoringBatteryOptimizations(context.packageName)
    } catch (t: Throwable) {
        false
    }

    // ── 授权动作 ────────────────────────────────────────────────────────

    /** 跳转「所有文件访问」系统设置页。返回是否成功发起。 */
    fun openAllFilesSettings(activity: Activity): Boolean = try {
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${activity.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (t: Throwable) {
        try {
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (t2: Throwable) {
            false
        }
    }

    /** 请求通知 + 旧版存储等运行时权限；结果经 [onRuntimeResult] 回给 Dart。 */
    fun requestRuntimePermissions(activity: Activity) {
        val wanted = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 && !notifGranted(activity)) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
        }
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2 &&
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            wanted += Manifest.permission.READ_EXTERNAL_STORAGE
            wanted += Manifest.permission.WRITE_EXTERNAL_STORAGE
        }
        if (wanted.isEmpty()) {
            emit(
                "runtimePermissions",
                mapOf("granted" to emptyMap<String, Boolean>()),
            )
            return
        }
        ActivityCompat.requestPermissions(activity, wanted.toTypedArray(), REQUEST_CODE_RUNTIME)
    }

    /** 宿主 Activity 的 onRequestPermissionsResult 转发进来。 */
    fun onRuntimeResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_CODE_RUNTIME) return
        val granted = mutableMapOf<String, Boolean>()
        for (i in permissions.indices) {
            granted[permissions[i]] =
                grantResults.getOrElse(i) { PackageManager.PERMISSION_DENIED } ==
                    PackageManager.PERMISSION_GRANTED
        }
        emit("runtimePermissions", mapOf("granted" to granted))
    }

    /** 请求电池优化豁免；已豁免时返回 true，否则弹系统对话框并返回 false。 */
    fun requestBatteryExemption(activity: Activity): Boolean {
        if (batteryExempt(activity)) return true
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            false
        } catch (t: Throwable) {
            false
        }
    }

    // ── Shizuku ─────────────────────────────────────────────────────────

    /** 发起 Shizuku 授权对话框；返回 false 表示当前没法发起。 */
    fun shizukuRequestPermission(): Boolean = try {
        if (Shizuku.pingBinder() && !Shizuku.isPreV11()) {
            Shizuku.requestPermission(REQUEST_CODE_SHIZUKU)
            true
        } else {
            false
        }
    } catch (t: Throwable) {
        false
    }

    /** 连接（或复用）Shizuku UserService；成功后回调 [onReady]。 */
    private fun bindShizukuService(activity: Activity, onReady: (IPrivilegedService) -> Unit) {
        shizukuService?.let(onReady)
        if (!shizukuConnecting.compareAndSet(false, true)) return
        try {
            val args = Shizuku.UserServiceArgs(
                ComponentName(activity, PrivilegedService::class.java),
            )
                .version(USER_SERVICE_VERSION)
                .processNameSuffix("privileged")
            Shizuku.bindUserService(
                args,
                object : ServiceConnection {
                    override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                        shizukuConnecting.set(false)
                        val svc = service?.let { IPrivilegedService.Stub.asInterface(it) }
                        if (svc == null) {
                            emit("shizukuService", mapOf("connected" to false))
                            return
                        }
                        shizukuService = svc
                        // 冲刷排队中的命令。
                        val queued = synchronized(pendingShizuku) {
                            pendingShizuku.toList().also { pendingShizuku.clear() }
                        }
                        onReady(svc)
                        for ((cmd, reply) in queued) {
                            runViaShizuku(svc, cmd, reply)
                        }
                    }

                    override fun onServiceDisconnected(name: ComponentName?) {
                        shizukuService = null
                    }
                },
            )
        } catch (t: Throwable) {
            shizukuConnecting.set(false)
            emit("shizukuService", mapOf("connected" to false, "error" to t.message))
        }
    }

    // ── Dhizuku ─────────────────────────────────────────────────────────

    /** 发起 Dhizuku 授权；返回 false 表示 Dhizuku 不可用。 */
    fun dhizukuRequestPermission(activity: Activity): Boolean = try {
        if (!Dhizuku.init(activity)) {
            false
        } else if (Dhizuku.isPermissionGranted()) {
            emit("dhizukuPermission", mapOf("granted" to true))
            true
        } else {
            Dhizuku.requestPermission(object : DhizukuRequestPermissionListener() {
                override fun onRequestPermission(grantResult: Int) {
                    emit(
                        "dhizukuPermission",
                        mapOf("granted" to (grantResult == PackageManager.PERMISSION_GRANTED)),
                    )
                }
            })
            true
        }
    } catch (t: Throwable) {
        false
    }

    // ── 特权命令 ────────────────────────────────────────────────────────

    /**
     * 以特权身份执行命令（`source` = `shizuku` / `dhizuku`）。
     * 阻塞操作 —— 后台线程跑，结果通过 [reply] 回主线程。
     */
    fun exec(
        activity: Activity,
        source: String,
        cmd: List<String>,
        reply: MethodChannel.Result,
    ) {
        thread(name = "priv-exec") {
            when (source) {
                "dhizuku" -> {
                    val result = try {
                        if (!Dhizuku.init(activity)) {
                            throw IllegalStateException("Dhizuku unavailable")
                        }
                        runProcess(Dhizuku.newProcess(cmd.toTypedArray(), null, null))
                    } catch (t: Throwable) {
                        errorResult(t)
                    }
                    mainHandler.post { reply.success(result) }
                }

                else -> {
                    val svc = shizukuService
                    if (svc != null) {
                        runViaShizuku(svc, cmd, reply)
                    } else {
                        synchronized(pendingShizuku) { pendingShizuku += cmd to reply }
                        mainHandler.post { bindShizukuService(activity) { } }
                    }
                }
            }
        }
    }

    private fun runViaShizuku(
        svc: IPrivilegedService,
        cmd: List<String>,
        reply: MethodChannel.Result,
    ) {
        thread(name = "priv-shizuku") {
            val result = try {
                parseServiceResult(svc.run(cmd.toTypedArray()))
            } catch (t: Throwable) {
                errorResult(t)
            }
            mainHandler.post { reply.success(result) }
        }
    }

    private fun runProcess(process: Process): Map<String, Any?> = try {
        var errText = ""
        val errReader = thread {
            errText = process.errorStream.bufferedReader().readText()
        }
        val outText = process.inputStream.bufferedReader().readText()
        errReader.join()
        mapOf("exit" to process.waitFor(), "out" to outText, "err" to errText)
    } catch (t: Throwable) {
        errorResult(t)
    }

    private fun parseServiceResult(json: String): Map<String, Any?> = try {
        val obj = JSONObject(json)
        mapOf(
            "exit" to obj.optInt("exit", -1),
            "out" to obj.optString("out"),
            "err" to obj.optString("err"),
        )
    } catch (t: Throwable) {
        mapOf("exit" to -1, "out" to "", "err" to json)
    }

    private fun errorResult(t: Throwable): Map<String, Any?> =
        mapOf("exit" to -1, "out" to "", "err" to (t.message ?: t.toString()))
}
