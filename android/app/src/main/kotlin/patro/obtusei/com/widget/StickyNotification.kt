package patro.obtusei.com.widget

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import patro.obtusei.com.R
import java.util.Calendar
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * An ongoing, silent notification with today's BS date, tithi and events.
 * Its status-bar icon is the day of the month (BS in Devanagari or AD, as
 * picked in Settings), or the Patro mark when that is turned off.
 */
object StickyNotification {
    private const val CHANNEL_ID = "patro_today"
    private const val NOTIFICATION_ID = 2083

    fun sync(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val snapshot = WidgetStore.load(context)
        if (snapshot?.sticky != true) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        if (!manager.areNotificationsEnabled()) return
        ensureChannel(context, manager)
        manager.notify(NOTIFICATION_ID, build(context, snapshot))
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notification_channel_today),
                // LOW keeps the status-bar icon but never makes a sound.
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = context.getString(R.string.notification_channel_today_description)
                setShowBadge(false)
            },
        )
    }

    private fun build(context: Context, snapshot: WidgetSnapshot): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setColor(snapshot.colors.accent)
            .setContentIntent(PatroWidgetViews.openAppIntent(context))

        val today = snapshot.today()
        if (today == null) {
            // The app has not published far enough ahead; show the AD date.
            val ad = PatroDates.todayKey()
            return builder
                .setSmallIcon(
                    if (snapshot.statusBarDate) {
                        dayIcon(context, Calendar.getInstance().get(Calendar.DAY_OF_MONTH).toString())
                    } else {
                        markIcon(context)
                    },
                )
                .setContentTitle(PatroDates.adLabel(ad))
                .setContentText(context.getString(R.string.widget_open_app_hint))
                .build()
        }

        val lines = listOfNotNull(today.tithi) + today.entries.map { it.label }
        return builder
            .setSmallIcon(statusIcon(context, snapshot, today))
            .setContentTitle(snapshot.longDate(today))
            .setContentText(lines.joinToString("  ·  "))
            .setSubText(PatroDates.adLabel(today.ad))
            .setStyle(Notification.BigTextStyle().bigText(lines.joinToString("\n")))
            .build()
    }

    private fun statusIcon(context: Context, snapshot: WidgetSnapshot, today: WidgetDay): Icon = when {
        !snapshot.statusBarDate -> markIcon(context)
        snapshot.statusBarBs -> dayIcon(context, PatroDates.devanagari(today.day.toString()))
        else -> dayIcon(context, today.adDay.toString())
    }

    private fun markIcon(context: Context): Icon =
        Icon.createWithResource(context, R.drawable.ic_stat_patro)

    /**
     * The status bar draws small icons as an alpha mask, so white text on a
     * transparent square shows up as the day numeral in the system's colour.
     */
    private fun dayIcon(context: Context, text: String): Icon {
        val size = (24 * context.resources.displayMetrics.density).roundToInt()
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
            textSize = size.toFloat()
        }
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        paint.textSize *= min(size * 0.98f / bounds.width(), size * 0.82f / bounds.height())
        paint.getTextBounds(text, 0, text.length, bounds)
        Canvas(bitmap).drawText(text, size / 2f, size / 2f - bounds.exactCenterY(), paint)
        return Icon.createWithBitmap(bitmap)
    }
}
