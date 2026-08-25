package com.excellentcalendar.excellent_calendar.android.ring

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.excellentcalendar.excellent_calendar.android.notification.AndroidNotificationChannelManager

class RingControlNotificationFactory(context: Context) {
    private val appContext = context.applicationContext

    fun build(session: RingSessionRecord, allowFullScreen: Boolean): Notification {
        val count = session.items.size
        val title = if (count == 1) "日程提醒" else "$count 个日程提醒"
        val body = if (session.phase == "quiet_pending") "响铃已静音，仍有提醒待处理" else "你有一个日程提醒"
        val viewIntent = PendingIntent.getActivity(
            appContext,
            ViewRequestCode,
            Intent(appContext, RingFullscreenActivity::class.java)
                .setAction(ActionView)
                .setData(Uri.parse("excellentcalendar://ring/${session.sessionId}")),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(appContext, AndroidNotificationChannelManager.RingControlChannelId)
        } else {
            Notification.Builder(appContext)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(viewIntent)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion())
            .addAction(action("关闭${if (count > 1) "全部" else ""}", RingActionReceiver.ActionStop, session, session.items.map { it.deliveryId }))
            .addAction(action("稍后${if (count > 1) "全部" else ""}", RingActionReceiver.ActionSnooze, session, session.items.map { it.deliveryId }))
        if (count == 1) {
            builder.addAction(action("完成", RingActionReceiver.ActionComplete, session, listOf(session.items.single().deliveryId)))
        } else {
            builder.addAction(Notification.Action.Builder(null, "查看", viewIntent).build())
        }
        if (allowFullScreen) builder.setFullScreenIntent(viewIntent, true)
        return builder.build()
    }

    private fun action(label: String, action: String, session: RingSessionRecord, deliveryIds: List<String>): Notification.Action {
        val intent = Intent(appContext, RingActionReceiver::class.java)
            .setAction(action)
            .setData(Uri.parse("excellentcalendar://ring/action/${action.substringAfterLast('.')}/${session.sessionId}/${session.revision}"))
            .putExtra(RingActionReceiver.ExtraDeliveryIds, deliveryIds.toTypedArray())
        val pending = PendingIntent.getBroadcast(
            appContext,
            (session.sessionId + action + session.revision).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, label, pending).build()
    }

    private fun publicVersion(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(appContext, AndroidNotificationChannelManager.RingControlChannelId)
        } else {
            Notification.Builder(appContext)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("日程提醒")
            .setContentText("你有一个日程提醒")
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
    }

    companion object {
        const val NotificationId = 7301
        const val ActionView = "excellent_calendar.action.VIEW_RING"
        private const val ViewRequestCode = 7302
    }
}
