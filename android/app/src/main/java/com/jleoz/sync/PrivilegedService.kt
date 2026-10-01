package com.jleoz.sync

import android.app.Service
import android.content.Intent
import android.os.IBinder
import kotlin.concurrent.thread
import org.json.JSONObject

/**
 * Shizuku UserService —— 以 shell（ADB）/root 身份运行的隔离进程，
 * 负责 `appops` / `pm` 等特权命令。不注册进 Manifest：由 Shizuku 通过
 * app_process 直接拉起（见 Privileged.bindShizukuService）。
 */
class PrivilegedService : Service() {

    private val binder = object : IPrivilegedService.Stub() {
        override fun run(cmd: Array<out String>): String = try {
            if (cmd.isEmpty()) {
                errorResult("empty command")
            } else {
                val process = ProcessBuilder(*cmd)
                    .redirectErrorStream(false)
                    .start()
                var errText = ""
                val errReader = thread {
                    errText = process.errorStream.bufferedReader().readText()
                }
                val outText = process.inputStream.bufferedReader().readText()
                errReader.join()
                val code = process.waitFor()
                JSONObject()
                    .put("exit", code)
                    .put("out", outText)
                    .put("err", errText)
                    .toString()
            }
        } catch (t: Throwable) {
            errorResult(t.message ?: t.toString())
        }
    }

    private fun errorResult(message: String): String = try {
        JSONObject()
            .put("exit", -1)
            .put("out", "")
            .put("err", message)
            .toString()
    } catch (t: Throwable) {
        """{"exit":-1,"out":"","err":"${message.replace("\"", "'")}"}"""
    }

    override fun onBind(intent: Intent?): IBinder = binder
}
