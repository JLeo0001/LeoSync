package com.jleoz.sync.Services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import com.jleoz.sync.R

/**
 * OAuth 授权期间的保活前台服务。
 *
 * 引擎在授权期间要维持 `127.0.0.1:53682` 上的本地回调服务器，等浏览器把
 * 授权码 302 回来。这个子进程是应用 exec 出来的「phantom process」：
 * 应用一旦进入缓存态（用户切到浏览器的那一刻），Android 12+ 会把它杀掉 ——
 * 表现就是浏览器里授权成功，回调却打不到引擎，授权永远完不成。
 *
 * 挂一个前台服务把应用进程顶在「前台服务」优先级（高于缓存态），子进程就能
 * 活到用户授权完成。成功、失败、取消都会由 Dart 侧立刻停掉它。
 */
class OauthKeepAliveService : Service() {

    override fun onCreate() {
        super.onCreate()
        val notification = buildNotification()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        // 一直等到 Dart 侧发来 ACTION_STOP（授权成功 / 失败 / 取消）。
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.oauth_keepalive_channel),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.oauth_keepalive_text))
            .setSmallIcon(R.drawable.ic_engine_logo)
            .setOngoing(true)
            .setContentIntent(null)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.jleoz.sync.oauth.KEEPALIVE_STOP"
        private const val CHANNEL_ID = "oauth_keepalive"
        private const val NOTIFICATION_ID = 4201
    }
}
