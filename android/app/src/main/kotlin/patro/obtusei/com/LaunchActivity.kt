package patro.obtusei.com

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * The launcher entry for the default icon. It opens [MainActivity] at once.
 *
 * The other icons are `<activity-alias>`es of [MainActivity]; this one has to
 * be a real activity so it can be turned off when another icon is picked
 * without turning off [MainActivity] itself (see [AppIcons]), and so
 * `flutter run`, which looks only for `<activity>` launchers, still finds it.
 */
class LaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Pass on extras such as the ones `flutter run` adds for tracing.
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = intent.action
                intent.extras?.let { putExtras(it) }
            },
        )
        finish()
    }
}
