package app.packingproof.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class OrderInfoReceiverForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "订单接收",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "工作期间在后台接收局域网订单信息"
                setShowBadge(false)
            },
        )
        startForeground(
            NOTIFICATION_ID,
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("正在接收订单信息")
                .setContentText("仅通过局域网接收油猴脚本数据")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setSilent(true)
                .build(),
        )
        OrderInfoReceiverRuntime.start(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val CHANNEL_ID = "order_info_receiver"
        private const val NOTIFICATION_ID = 5281
    }
}
