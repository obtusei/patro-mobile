package patro.obtusei.com.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import patro.obtusei.com.reminder.EventReminders
import java.util.Calendar

/** Redraws every widget and the sticky notification, then re-arms the midnight alarm. */
object PatroRefresh {
    const val ACTION_REFRESH = "patro.obtusei.com.action.REFRESH"

    fun all(context: Context) {
        for (provider in PatroWidgetProvider.all()) provider.updateAll(context)
        StickyNotification.sync(context)
        scheduleNextMidnight(context)
    }

    fun scheduleNextMidnight(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val intent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, DayChangeReceiver::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val needed = PatroWidgetProvider.anyPlaced(context) ||
            WidgetStore.load(context)?.sticky == true
        if (!needed) {
            alarms.cancel(intent)
            return
        }

        val midnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

        // Exact alarms need the user's consent on Android 14+; without it the
        // date may roll over a few minutes late.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, midnight, intent)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, midnight, intent)
        }
    }
}

/** Midnight alarm, reboot, clock or timezone change: the date shown may be stale. */
class DayChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PatroRefresh.all(context)
        // Reboots clear alarms, and clock changes move when reminders are due.
        if (intent.action != PatroRefresh.ACTION_REFRESH) EventReminders.rescheduleAll(context)
    }
}
