package patro.obtusei.com

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import patro.obtusei.com.reminder.EventReminders
import patro.obtusei.com.widget.PatroRefresh
import patro.obtusei.com.widget.WidgetStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // See lib/services/widget_bridge.dart.
        val widgets = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "patro/widgets")
        widgetChannel = widgets
        widgets.setMethodCallHandler { call, result ->
            when (call.method) {
                // The day a widget opened the app on, asked once when Dart starts.
                "takeLaunchDay" -> result.success(takeDay(intent))
                "publish" -> {
                    val raw = call.arguments as? String
                    if (raw == null) {
                        result.error("bad_args", "publish expects a JSON string", null)
                        return@setMethodCallHandler
                    }
                    WidgetStore.save(this, raw)
                    if (WidgetStore.load(this)?.sticky == true) requestNotificationPermission()
                    PatroRefresh.all(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // See lib/services/system_bridge.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "patro/system")
            .setMethodCallHandler { call, result ->
                val argument = call.arguments as? String
                if (argument == null) {
                    result.error("bad_args", "${call.method} expects a string", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "scheduleReminders" -> {
                        EventReminders.replace(this, argument)
                        if (EventReminders.hasAny(this)) requestReminderPermission()
                        result.success(null)
                    }
                    "setAppIcon" -> {
                        if (AppIcons.apply(this, argument)) {
                            result.success(null)
                        } else {
                            result.error("bad_args", "Unknown app icon $argument", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** A widget tapped while the app is already running. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val day = takeDay(intent) ?: return
        widgetChannel?.invokeMethod("openDay", day)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        widgetChannel?.setMethodCallHandler(null)
        widgetChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** The day in a widget's `patro://day/yyyy-MM-dd` link, handed over only once. */
    private fun takeDay(intent: Intent?): String? {
        val day = dayFrom(intent) ?: return null
        intent?.data = null
        return day
    }

    /** Android 13+ needs consent before the sticky notification can show. Asked once. */
    private fun requestNotificationPermission() {
        if (WidgetStore.askedForNotifications(this)) return
        if (!needsNotificationPermission()) return
        WidgetStore.markAskedForNotifications(this)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    /** The first event with a reminder asks too, even if the sticky prompt was declined. */
    private fun requestReminderPermission() {
        if (EventReminders.askedForPermission(this)) return
        if (!needsNotificationPermission()) return
        EventReminders.markAskedForPermission(this)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    private fun needsNotificationPermission() =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_REQUEST) PatroRefresh.all(this)
    }

    companion object {
        private const val NOTIFICATION_REQUEST = 2083
        private val DAY = Regex("""\d{4}-\d{2}-\d{2}""")

        /** Opens the app on [ad], a yyyy-MM-dd date; see lib/services/widget_bridge.dart. */
        fun dayUri(ad: String): Uri = Uri.parse("patro://day/$ad")

        fun dayFrom(intent: Intent?): String? {
            val data = intent?.data ?: return null
            if (data.scheme != "patro" || data.host != "day") return null
            return data.lastPathSegment?.takeIf { DAY.matches(it) }
        }
    }
}
