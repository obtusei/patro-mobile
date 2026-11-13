package patro.obtusei.com.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import patro.obtusei.com.MainActivity
import patro.obtusei.com.R
import java.util.Calendar
import java.util.Locale

/** Shared plumbing for the Patro home-screen widgets. */
abstract class PatroWidgetProvider : AppWidgetProvider() {
    abstract fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews

    override fun onUpdate(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
        for (id in widgetIds) manager.updateAppWidget(id, render(context, manager, id))
        PatroRefresh.scheduleNextMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        newOptions: Bundle,
    ) {
        manager.updateAppWidget(widgetId, render(context, manager, widgetId))
    }

    override fun onDisabled(context: Context) {
        PatroRefresh.scheduleNextMidnight(context)
    }

    /** Ids of this kind of widget placed on the home screen. */
    fun ids(context: Context): IntArray =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, javaClass))

    /** Redraws every placed widget of this kind. */
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (id in ids(context)) manager.updateAppWidget(id, render(context, manager, id))
    }

    companion object {
        /** One of each widget kind; every new provider must be listed here. */
        fun all(): List<PatroWidgetProvider> = listOf(
            TodayWidgetProvider(),
            MonthWidgetProvider(),
            AgendaWidgetProvider(),
            DateWidgetProvider(),
            HolidayWidgetProvider(),
        )

        fun anyPlaced(context: Context) = all().any { it.ids(context).isNotEmpty() }
    }
}

/** Today's BS date, AD date, tithi and events. */
class TodayWidgetProvider : PatroWidgetProvider() {
    override fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val snapshot = WidgetStore.load(context)
        val colors = snapshot?.colors ?: WidgetColors.DEFAULT
        val dim = PatroWidgetViews.withAlpha(colors.ink, 0.62f)
        val views = RemoteViews(context.packageName, R.layout.widget_today)

        PatroWidgetViews.tint(views, R.id.widget_bg, colors.background)
        PatroWidgetViews.tint(views, R.id.today_divider, PatroWidgetViews.withAlpha(colors.ink, 0.14f))
        views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openAppIntent(context))
        views.removeAllViews(R.id.today_events)

        val today = snapshot?.today()
        if (snapshot == null || today == null) {
            val now = Calendar.getInstance()
            views.setTextViewText(R.id.today_day, now.get(Calendar.DAY_OF_MONTH).toString())
            views.setTextViewText(
                R.id.today_month,
                now.getDisplayName(Calendar.MONTH, Calendar.LONG, Locale.ENGLISH),
            )
            views.setTextViewText(R.id.today_year, now.get(Calendar.YEAR).toString())
            views.setTextViewText(
                R.id.today_weekday,
                now.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.LONG, Locale.ENGLISH),
            )
            views.setViewVisibility(R.id.today_ad, View.GONE)
            views.setTextViewText(R.id.today_tithi, context.getString(R.string.widget_open_app_hint))
            views.setTextColor(R.id.today_day, colors.ink)
            views.setTextColor(R.id.today_month, colors.accent)
            views.setTextColor(R.id.today_year, dim)
            views.setTextColor(R.id.today_weekday, colors.ink)
            views.setTextColor(R.id.today_tithi, dim)
            return views
        }

        val dayColor = if (today.isRestDay) colors.holiday else colors.ink
        views.setTextViewText(R.id.today_day, snapshot.digits(today.day))
        views.setTextColor(R.id.today_day, dayColor)
        views.setTextViewText(R.id.today_month, snapshot.months[today.month - 1])
        views.setTextColor(R.id.today_month, colors.accent)
        views.setTextViewText(R.id.today_year, snapshot.digits(today.year))
        views.setTextColor(R.id.today_year, dim)
        views.setTextViewText(R.id.today_weekday, snapshot.weekdays[today.weekday - 1])
        views.setTextColor(R.id.today_weekday, dayColor)
        views.setViewVisibility(R.id.today_ad, View.VISIBLE)
        views.setTextViewText(R.id.today_ad, PatroDates.adLabel(today.ad))
        views.setTextColor(R.id.today_ad, dim)
        views.setViewVisibility(R.id.today_tithi, if (today.tithi == null) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.today_tithi, today.tithi.orEmpty())
        views.setTextColor(R.id.today_tithi, colors.accent)

        val height = PatroWidgetViews.heightOf(manager, widgetId, 110)
        val rows = ((height - 76) / 18).coerceIn(1, 5)
        PatroWidgetViews.addEntries(
            context, views, R.id.today_events, today.entries, rows, colors,
            context.getString(R.string.widget_no_events),
        )
        return views
    }
}

/**
 * A BS month grid that pages back and forth through the published range.
 *
 * Tapping a day picks it and lists its events under the grid; tapping the
 * picked day again opens it in the app, as on the app's own month page.
 */
class MonthWidgetProvider : PatroWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            super.onReceive(context, intent)
            return
        }
        when (intent.action) {
            ACTION_SHIFT -> {
                val delta = intent.getIntExtra(EXTRA_DELTA, 0)
                val snapshot = WidgetStore.load(context)
                if (delta == 0 || snapshot == null) {
                    WidgetStore.clearMonthOffset(context, widgetId)
                } else {
                    // Step from the month on screen, which may be clamped to the published range.
                    val current = snapshot.currentMonthIndex()
                    val target = (shownIndex(context, snapshot, widgetId) + delta)
                        .coerceIn(0, snapshot.monthKeys.lastIndex)
                    WidgetStore.setMonthOffset(context, widgetId, target - current)
                }
                // A new month starts on today or its 1st again.
                WidgetStore.clearMonthSelection(context, widgetId)
            }
            ACTION_SELECT -> {
                val ad = intent.getStringExtra(EXTRA_AD) ?: return
                WidgetStore.setMonthSelection(context, widgetId, ad)
            }
            else -> {
                super.onReceive(context, intent)
                return
            }
        }
        val manager = AppWidgetManager.getInstance(context)
        manager.updateAppWidget(widgetId, render(context, manager, widgetId))
    }

    override fun onDeleted(context: Context, widgetIds: IntArray) {
        for (id in widgetIds) {
            WidgetStore.clearMonthOffset(context, id)
            WidgetStore.clearMonthSelection(context, id)
        }
    }

    override fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val snapshot = WidgetStore.load(context)
        val colors = snapshot?.colors ?: WidgetColors.DEFAULT
        val dim = PatroWidgetViews.withAlpha(colors.ink, 0.55f)
        val views = RemoteViews(context.packageName, R.layout.widget_month)

        PatroWidgetViews.tint(views, R.id.widget_bg, colors.background)
        PatroWidgetViews.tint(views, R.id.month_prev, colors.ink)
        PatroWidgetViews.tint(views, R.id.month_next, colors.ink)
        PatroWidgetViews.tint(views, R.id.month_panel_divider, PatroWidgetViews.withAlpha(colors.ink, 0.14f))
        views.setTextColor(R.id.month_title, colors.accent)
        views.setTextColor(R.id.month_subtitle, dim)
        views.removeAllViews(R.id.month_weekdays)
        views.removeAllViews(R.id.month_grid)
        views.removeAllViews(R.id.month_panel_events)
        views.setViewVisibility(R.id.month_panel, View.GONE)

        if (snapshot == null || snapshot.monthKeys.isEmpty()) {
            views.setTextViewText(R.id.month_title, context.getString(R.string.app_name))
            views.setTextViewText(R.id.month_subtitle, context.getString(R.string.widget_open_app_hint))
            views.setViewVisibility(R.id.month_prev, View.INVISIBLE)
            views.setViewVisibility(R.id.month_next, View.INVISIBLE)
            views.setOnClickPendingIntent(R.id.month_title_box, PatroWidgetViews.openAppIntent(context))
            views.setOnClickPendingIntent(R.id.month_grid, PatroWidgetViews.openAppIntent(context))
            return views
        }

        val current = snapshot.currentMonthIndex()
        val index = shownIndex(context, snapshot, widgetId)
        val days = snapshot.daysOf(snapshot.monthKeys[index])
        val first = days.first()
        val todayKey = PatroDates.todayKey()
        val picked = WidgetStore.monthSelection(context, widgetId)
        val selected = days.firstOrNull { it.ad == picked }
            ?: days.firstOrNull { it.ad == todayKey }
            ?: first

        views.setTextViewText(R.id.month_title, snapshot.monthTitle(first))
        views.setTextViewText(R.id.month_subtitle, PatroDates.adSpan(first.ad, days.last().ad))

        // Tapping the title jumps back to this month, or opens the app when already there.
        views.setOnClickPendingIntent(
            R.id.month_title_box,
            if (index == current) PatroWidgetViews.openAppIntent(context) else shiftIntent(context, widgetId, 0),
        )
        bindArrow(context, views, R.id.month_prev, widgetId, -1, enabled = index > 0)
        bindArrow(context, views, R.id.month_next, widgetId, 1, enabled = index < snapshot.monthKeys.lastIndex)

        // NepaliDateTime weekdays: Sunday = 1 … Saturday = 7.
        val order = if (snapshot.weekStartsMonday) listOf(2, 3, 4, 5, 6, 7, 1) else (1..7).toList()
        for (weekday in order) {
            val cell = RemoteViews(context.packageName, R.layout.widget_month_weekday)
            cell.setTextViewText(R.id.weekday_label, snapshot.weekdaysShort[weekday - 1])
            cell.setTextColor(R.id.weekday_label, if (weekday in snapshot.weekendDays) colors.holiday else dim)
            views.addView(R.id.month_weekdays, cell)
        }

        // Today is a solid fill; the picked day a faint wash with a ring, so the
        // two never read alike even where a theme's accent matches its highlight.
        // A highlight too close to the background gives way to the ink.
        val mark = PatroWidgetViews.visibleOn(colors.highlight, colors.background, fallback = colors.ink)
        val onHighlight = PatroWidgetViews.onColor(mark)
        val wash = PatroWidgetViews.blend(mark, colors.background, 0.18f)
        val lead = order.indexOf(first.weekday)
        val cells = List(lead) { null } + days
        for (week in cells.chunked(7)) {
            val row = RemoteViews(context.packageName, R.layout.widget_month_row)
            for (column in 0 until 7) {
                val day = week.getOrNull(column)
                val cell = RemoteViews(context.packageName, R.layout.widget_month_cell)
                if (day == null) {
                    cell.setTextViewText(R.id.cell_day, "")
                    cell.setTextViewText(R.id.cell_ad, "")
                    row.addView(R.id.month_row, cell)
                    continue
                }
                val isToday = day.ad == todayKey
                val isSelected = day.ad == selected.ad
                cell.setTextViewText(R.id.cell_day, snapshot.digits(day.day))
                cell.setTextViewText(R.id.cell_ad, day.adDay.toString())
                cell.setTextColor(
                    R.id.cell_day,
                    when {
                        isToday -> onHighlight
                        day.isRestDay -> colors.holiday
                        else -> colors.ink
                    },
                )
                cell.setTextColor(
                    R.id.cell_ad,
                    if (isToday) PatroWidgetViews.withAlpha(onHighlight, 0.75f) else dim,
                )
                if (isToday) {
                    cell.setViewVisibility(R.id.cell_mark, View.VISIBLE)
                    PatroWidgetViews.tint(cell, R.id.cell_mark, mark)
                } else if (isSelected) {
                    cell.setViewVisibility(R.id.cell_mark, View.VISIBLE)
                    PatroWidgetViews.tint(cell, R.id.cell_mark, wash)
                    cell.setViewVisibility(R.id.cell_ring, View.VISIBLE)
                    PatroWidgetViews.tint(cell, R.id.cell_ring, mark)
                }
                if (day.entries.isNotEmpty()) {
                    val dot = day.entries.firstNotNullOfOrNull { it.color }
                        ?: if (day.entries.any { it.isHoliday }) colors.holiday else colors.accent
                    cell.setViewVisibility(R.id.cell_dot, View.VISIBLE)
                    PatroWidgetViews.tint(cell, R.id.cell_dot, if (isToday) onHighlight else dot)
                }
                cell.setOnClickPendingIntent(
                    R.id.cell_root,
                    if (isSelected) {
                        PatroWidgetViews.openDayIntent(context, day.ad)
                    } else {
                        selectIntent(context, widgetId, day.ad)
                    },
                )
                row.addView(R.id.month_row, cell)
            }
            views.addView(R.id.month_grid, row)
        }

        bindPanel(context, views, snapshot, selected, PatroWidgetViews.heightOf(manager, widgetId, 250))
        return views
    }

    /** The picked day's events under the grid, when the widget is tall enough for them. */
    private fun bindPanel(
        context: Context,
        views: RemoteViews,
        snapshot: WidgetSnapshot,
        day: WidgetDay,
        height: Int,
    ) {
        if (height < PANEL_MIN_HEIGHT) return
        val colors = snapshot.colors
        views.setViewVisibility(R.id.month_panel, View.VISIBLE)
        views.setOnClickPendingIntent(R.id.month_panel, PatroWidgetViews.openDayIntent(context, day.ad))
        views.setTextViewText(R.id.month_panel_title, snapshot.shortDate(day) + ", " + snapshot.weekdays[day.weekday - 1])
        views.setTextColor(R.id.month_panel_title, if (day.isRestDay) colors.holiday else colors.ink)
        views.setViewVisibility(R.id.month_panel_tithi, if (day.tithi == null) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.month_panel_tithi, day.tithi.orEmpty())
        views.setTextColor(R.id.month_panel_tithi, colors.accent)
        val rows = ((height - PANEL_MIN_HEIGHT) / 18 + 1).coerceIn(1, 4)
        PatroWidgetViews.addEntries(
            context, views, R.id.month_panel_events, day.entries, rows, colors,
            context.getString(R.string.widget_no_events_day),
        )
    }

    private fun shownIndex(context: Context, snapshot: WidgetSnapshot, widgetId: Int) =
        (snapshot.currentMonthIndex() + WidgetStore.monthOffset(context, widgetId))
            .coerceIn(0, snapshot.monthKeys.lastIndex)

    private fun bindArrow(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        widgetId: Int,
        delta: Int,
        enabled: Boolean,
    ) {
        views.setInt(viewId, "setImageAlpha", if (enabled) 255 else 60)
        if (enabled) views.setOnClickPendingIntent(viewId, shiftIntent(context, widgetId, delta))
    }

    private fun shiftIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
        val intent = Intent(context, MonthWidgetProvider::class.java)
            .setAction(ACTION_SHIFT)
            .setData(Uri.parse("patro-widget://month/$widgetId/shift/$delta"))
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            .putExtra(EXTRA_DELTA, delta)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** The data URI keeps one PendingIntent per day and widget; extras alone would collide. */
    private fun selectIntent(context: Context, widgetId: Int, ad: String): PendingIntent {
        val intent = Intent(context, MonthWidgetProvider::class.java)
            .setAction(ACTION_SELECT)
            .setData(Uri.parse("patro-widget://month/$widgetId/select/$ad"))
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            .putExtra(EXTRA_AD, ad)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        const val ACTION_SHIFT = "patro.obtusei.com.action.SHIFT_MONTH"
        const val ACTION_SELECT = "patro.obtusei.com.action.SELECT_DAY"
        const val EXTRA_DELTA = "delta"
        const val EXTRA_AD = "ad"

        /** Header, weekdays and six squeezed rows of days leave room for the panel above this. */
        const val PANEL_MIN_HEIGHT = 290
    }
}

object PatroWidgetViews {
    fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Opens the app on one day's page; see [MainActivity.dayFrom]. */
    fun openDayIntent(context: Context, ad: String): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(MainActivity.dayUri(ad))
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Usable height in dp; portrait launchers report it as MAX_HEIGHT. */
    fun heightOf(manager: AppWidgetManager, widgetId: Int, fallback: Int): Int =
        manager.getAppWidgetOptions(widgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, fallback)
            .takeIf { it > 0 } ?: fallback

    /** Recolours a white shape drawable in an ImageView. */
    fun tint(views: RemoteViews, viewId: Int, color: Int) {
        views.setInt(viewId, "setColorFilter", color)
    }

    fun withAlpha(color: Int, alpha: Float): Int =
        (color and 0x00FFFFFF) or ((Color.alpha(color) * alpha).toInt() shl 24)

    /** WCAG contrast ratio between two opaque colours, from 1 to 21. */
    fun contrast(a: Int, b: Int): Double {
        val la = Color.luminance(a) + 0.05
        val lb = Color.luminance(b) + 0.05
        return if (la > lb) la / lb else lb / la
    }

    /** Black or white, whichever reads better on [fill]. */
    fun onColor(fill: Int): Int =
        if (contrast(fill, Color.BLACK) >= contrast(fill, Color.WHITE)) Color.BLACK else Color.WHITE

    /** [color], or [fallback] when [color] would barely show on [background]. */
    fun visibleOn(color: Int, background: Int, fallback: Int, minContrast: Double = 1.8): Int =
        if (contrast(color, background) >= minContrast) color else fallback

    /** [top] laid over [bottom] at [alpha], as an opaque colour. */
    fun blend(top: Int, bottom: Int, alpha: Float): Int {
        fun mix(t: Int, b: Int) = (t * alpha + b * (1 - alpha)).toInt().coerceIn(0, 255)
        return Color.rgb(
            mix(Color.red(top), Color.red(bottom)),
            mix(Color.green(top), Color.green(bottom)),
            mix(Color.blue(top), Color.blue(bottom)),
        )
    }

    fun entryDot(entry: WidgetEntry, colors: WidgetColors): Int =
        entry.color ?: if (entry.isHoliday) colors.holiday else colors.accent

    /** Up to [rows] lines of [entries], the last one turning into "+n more" if they overflow. */
    fun addEntries(
        context: Context,
        views: RemoteViews,
        containerId: Int,
        entries: List<WidgetEntry>,
        rows: Int,
        colors: WidgetColors,
        emptyText: String?,
    ) {
        val dim = withAlpha(colors.ink, 0.62f)
        if (entries.isEmpty()) {
            if (emptyText != null) views.addView(containerId, eventRow(context, emptyText, null, dim))
            return
        }
        val shown = if (entries.size > rows) (rows - 1).coerceAtLeast(0) else entries.size
        for (entry in entries.take(shown)) {
            views.addView(containerId, eventRow(context, entry.label, entryDot(entry, colors), colors.ink))
        }
        if (shown < entries.size) {
            val more = context.getString(R.string.widget_more_events, entries.size - shown)
            views.addView(containerId, eventRow(context, more, null, dim))
        }
    }

    fun eventRow(context: Context, text: String, dotColor: Int?, textColor: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.widget_event_row)
        row.setTextViewText(R.id.event_text, text)
        row.setTextColor(R.id.event_text, textColor)
        if (dotColor == null) {
            row.setViewVisibility(R.id.event_dot, View.GONE)
        } else {
            tint(row, R.id.event_dot, dotColor)
        }
        return row
    }
}
