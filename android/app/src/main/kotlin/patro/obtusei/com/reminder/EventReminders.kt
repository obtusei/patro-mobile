package patro.obtusei.com.reminder

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import patro.obtusei.com.R
import patro.obtusei.com.widget.PatroWidgetViews
import patro.obtusei.com.widget.WidgetStore

/**
 * Event reminder notifications. The app hands over its next reminders (see
 * lib/providers/reminder_sync_provider.dart); each becomes an alarm that
 * posts a notification. The list is stored so alarms can be set again after
 * a reboot or clock change, which clear them.
 */
object EventReminders {
    private const val CHANNEL_ID = "patro_reminders"
    private const val PREFS = "patro_reminders"
    private const val KEY_LIST = "list"
    private const val KEY_ASKED_PERMISSION = "asked_permission"
    private const val ACTION_REMIND = "patro.obtusei.com.action.REMIND"
    private const val EXTRA_TITLE = "title"
    private const val EXTRA_TEXT = "text"
    private const val EXTRA_AT = "at"

    private data class Reminder(val key: String, val at: Long, val title: String, val text: String)

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Replaces every scheduled reminder with those in [raw], a JSON list. */
    fun replace(context: Context, raw: String) {
        val previous = load(context)
        val next = parse(raw)
        prefs(context).edit().putString(KEY_LIST, raw).apply()
        val keep = next.map { it.key }.toSet()
        for (old in previous) if (old.key !in keep) cancel(context, old)
        schedule(context, next)
    }

    /** Sets every stored, still-future reminder again. */
    fun rescheduleAll(context: Context) = schedule(context, load(context))

    fun hasAny(context: Context) = load(context).isNotEmpty()

    fun askedForPermission(context: Context) = prefs(context).getBoolean(KEY_ASKED_PERMISSION, false)

    fun markAskedForPermission(context: Context) {
        prefs(context).edit().putBoolean(KEY_ASKED_PERMISSION, true).apply()
    }

    private fun load(context: Context): List<Reminder> =
        prefs(context).getString(KEY_LIST, null)?.let(::parse) ?: emptyList()

    private fun parse(raw: String): List<Reminder> = try {
        val list = JSONArray(raw)
        (0 until list.length()).map { i ->
            val o = list.getJSONObject(i)
            Reminder(o.getString("key"), o.getLong("at"), o.getString("title"), o.optString("text"))
        }
    } catch (e: Exception) {
        android.util.Log.w("Patro", "Unreadable reminder list", e)
        emptyList()
    }

    private fun schedule(context: Context, reminders: List<Reminder>) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val now = System.currentTimeMillis()
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        for (r in reminders) {
            if (r.at <= now) continue
            val intent = pendingIntent(context, r, PendingIntent.FLAG_UPDATE_CURRENT) ?: continue
            if (exact) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.at, intent)
            } else {
                // Without exact-alarm access Android may deliver a few minutes late.
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.at, intent)
            }
        }
    }

    private fun cancel(context: Context, r: Reminder) {
        val intent = pendingIntent(context, r, PendingIntent.FLAG_NO_CREATE) ?: return
        context.getSystemService(AlarmManager::class.java)?.cancel(intent)
        intent.cancel()
    }

    /** One alarm per reminder, told apart by its data URI. */
    private fun pendingIntent(context: Context, r: Reminder, flags: Int): PendingIntent? =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ReminderReceiver::class.java)
                .setAction(ACTION_REMIND)
                .setData(Uri.fromParts("patro-reminder", r.key, null))
                .putExtra(EXTRA_TITLE, r.title)
                .putExtra(EXTRA_TEXT, r.text)
                .putExtra(EXTRA_AT, r.at),
            flags or PendingIntent.FLAG_IMMUTABLE,
        )

    fun show(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) return
        ensureChannel(context, manager)
        val key = intent.data?.schemeSpecificPart ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        builder
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE))
            .setContentText(intent.getStringExtra(EXTRA_TEXT))
            .setWhen(intent.getLongExtra(EXTRA_AT, System.currentTimeMillis()))
            .setShowWhen(true)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setContentIntent(PatroWidgetViews.openAppIntent(context))
        WidgetStore.load(context)?.let { builder.setColor(it.colors.accent) }
        manager.notify(key, 0, builder.build())
    }

    private fun ensureChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.notification_channel_reminders),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = context.getString(R.string.notification_channel_reminders_description)
            },
        )
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        EventReminders.show(context, intent)
    }
}
