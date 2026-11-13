package patro.obtusei.com

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Switches the launcher icon by turning on one launcher entry in
 * AndroidManifest.xml and off the rest. Ids match `appIcons` in
 * lib/models/app_icon.dart.
 */
object AppIcons {
    private const val DEFAULT = "classic"

    private val entries = mapOf(
        DEFAULT to "patro.obtusei.com.LaunchActivity",
        "obsidian" to "patro.obtusei.com.IconObsidian",
        "snow" to "patro.obtusei.com.IconSnow",
        "midnight" to "patro.obtusei.com.IconMidnight",
        "chalkboard" to "patro.obtusei.com.IconChalkboard",
        "rhododendron" to "patro.obtusei.com.IconRhododendron",
        "himalaya" to "patro.obtusei.com.IconHimalaya",
    )

    /** Returns false for an unknown id. Does nothing if [id] is already on. */
    fun apply(context: Context, id: String): Boolean {
        val target = entries[id] ?: return false
        val pm = context.packageManager
        // Turn the new entry on first so the app never drops off the launcher.
        setEnabled(context, pm, target, enabledByDefault = id == DEFAULT, on = true)
        for ((otherId, name) in entries) {
            if (name != target) {
                setEnabled(context, pm, name, enabledByDefault = otherId == DEFAULT, on = false)
            }
        }
        return true
    }

    private fun setEnabled(
        context: Context,
        pm: PackageManager,
        name: String,
        enabledByDefault: Boolean,
        on: Boolean,
    ) {
        val component = ComponentName(context.packageName, name)
        val now = when (pm.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> enabledByDefault
            else -> false
        }
        if (now == on) return
        pm.setComponentEnabledSetting(
            component,
            if (on) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP,
        )
    }
}
