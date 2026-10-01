package com.jleoz.sync.notifications

import android.app.NotificationManager
import android.content.Context
import android.os.Build

class DiscardChannels {
    companion object {
        fun discard(context: Context) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notificationManager.deleteNotificationChannel("com.jleoz.sync.UPLOAD_CHANNEL")
                notificationManager.deleteNotificationChannel("com.jleoz.sync.DOWNLOAD_CHANNEL")
            }

        }
    }
}