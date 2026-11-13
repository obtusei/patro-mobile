package patro.obtusei.com.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import patro.obtusei.com.R
import java.util.Calendar
import java.util.Locale

/** The next days that have holidays, festivals or the user's events, each opening its day. */
class AgendaWidgetProvider : PatroWidgetProvider() {
    override fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val snapshot = WidgetStore.load(context)
        val colors = snapshot?.colors ?: WidgetColors.DEFAULT
        val dim = PatroWidgetViews.withAlpha(colors.ink, 0.62f)
        val views = RemoteViews(context.packageName, R.layout.widget_agenda)

        PatroWidgetViews.tint(views, R.id.widget_bg, colors.background)
        views.setTextColor(R.id.agenda_title, colors.accent)
        views.setTextColor(R.id.agenda_today, dim)
        views.removeAllViews(R.id.agenda_list)
        views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openAppIntent(context))

        val upcoming = snapshot?.daysFromToday().orEmpty()
        val today = upcoming.firstOrNull()?.takeIf { it.ad == PatroDates.todayKey() }
        if (snapshot == null || today == null) {
            views.setTextViewText(R.id.agenda_today, "")
            views.addView(
                R.id.agenda_list,
                PatroWidgetViews.eventRow(context, context.getString(R.string.widget_open_app_hint), null, dim),
            )
            return views
        }
        views.setTextViewText(R.id.agenda_today, snapshot.shortDate(today))
        views.setOnClickPendingIntent(R.id.agenda_head, PatroWidgetViews.openDayIntent(context, today.ad))

        // Lines of about 18dp below a 24dp header and the padding.
        var lines = ((PatroWidgetViews.heightOf(manager, widgetId, 180) - 48) / 18).coerceAtLeast(2)
        var added = 0
        for ((offset, day) in upcoming.withIndex()) {
            if (day.entries.isEmpty()) continue
            // Each day takes its heading and at least one entry.
            if (lines < 2) break
            val group = RemoteViews(context.packageName, R.layout.widget_agenda_day)
            val label = when (offset) {
                0 -> context.getString(R.string.widget_today_word)
                1 -> context.getString(R.string.widget_tomorrow)
                else -> snapshot.weekdays[day.weekday - 1]
            }
            group.setTextViewText(R.id.agenda_day_title, "$label · ${snapshot.shortDate(day)}")
            group.setTextColor(R.id.agenda_day_title, if (day.isRestDay) colors.holiday else colors.ink)
            group.setTextViewText(R.id.agenda_day_ad, PatroDates.adShort(day.ad))
            group.setTextColor(R.id.agenda_day_ad, dim)
            val rows = minOf(lines - 1, 3)
            PatroWidgetViews.addEntries(context, group, R.id.agenda_day_events, day.entries, rows, colors, null)
            group.setOnClickPendingIntent(R.id.agenda_day, PatroWidgetViews.openDayIntent(context, day.ad))
            views.addView(R.id.agenda_list, group)
            lines -= 1 + minOf(rows, day.entries.size)
            added++
        }
        if (added == 0) {
            views.addView(
                R.id.agenda_list,
                PatroWidgetViews.eventRow(context, context.getString(R.string.widget_nothing_upcoming), null, dim),
            )
        }
        return views
    }
}

/** A small tile with today's BS date. */
class DateWidgetProvider : PatroWidgetProvider() {
    override fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val snapshot = WidgetStore.load(context)
        val colors = snapshot?.colors ?: WidgetColors.DEFAULT
        val dim = PatroWidgetViews.withAlpha(colors.ink, 0.62f)
        val views = RemoteViews(context.packageName, R.layout.widget_date)

        PatroWidgetViews.tint(views, R.id.widget_bg, colors.background)
        views.setTextColor(R.id.date_month, colors.accent)
        views.setTextColor(R.id.date_ad, dim)
        views.setTextColor(R.id.date_tithi, colors.accent)

        // Small tiles drop the AD date and tithi, then the weekday.
        val height = PatroWidgetViews.heightOf(manager, widgetId, 110)
        val roomy = height >= 130
        views.setViewVisibility(R.id.date_weekday, if (height >= 90) View.VISIBLE else View.GONE)
        views.setViewVisibility(R.id.date_ad, if (roomy) View.VISIBLE else View.GONE)

        val today = snapshot?.today()
        if (snapshot == null || today == null) {
            val now = Calendar.getInstance()
            views.setTextViewText(R.id.date_weekday, now.getDisplayName(Calendar.DAY_OF_WEEK, Calendar.LONG, Locale.ENGLISH))
            views.setTextViewText(R.id.date_day, now.get(Calendar.DAY_OF_MONTH).toString())
            views.setTextViewText(R.id.date_month, now.getDisplayName(Calendar.MONTH, Calendar.LONG, Locale.ENGLISH))
            views.setTextColor(R.id.date_weekday, colors.ink)
            views.setTextColor(R.id.date_day, colors.ink)
            views.setViewVisibility(R.id.date_ad, View.GONE)
            views.setViewVisibility(R.id.date_tithi, View.GONE)
            views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openAppIntent(context))
            return views
        }

        val dayColor = if (today.isRestDay) colors.holiday else colors.ink
        views.setTextViewText(R.id.date_weekday, snapshot.weekdays[today.weekday - 1])
        views.setTextColor(R.id.date_weekday, dayColor)
        views.setTextViewText(R.id.date_day, snapshot.digits(today.day))
        views.setTextColor(R.id.date_day, dayColor)
        views.setTextViewText(R.id.date_month, snapshot.monthTitle(today))
        views.setTextViewText(R.id.date_ad, PatroDates.adLabel(today.ad))
        views.setViewVisibility(R.id.date_tithi, if (roomy && today.tithi != null) View.VISIBLE else View.GONE)
        views.setTextViewText(R.id.date_tithi, today.tithi.orEmpty())
        views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openDayIntent(context, today.ad))
        return views
    }
}

/** Counts down to the next public holiday. */
class HolidayWidgetProvider : PatroWidgetProvider() {
    override fun render(context: Context, manager: AppWidgetManager, widgetId: Int): RemoteViews {
        val snapshot = WidgetStore.load(context)
        val colors = snapshot?.colors ?: WidgetColors.DEFAULT
        val dim = PatroWidgetViews.withAlpha(colors.ink, 0.62f)
        val views = RemoteViews(context.packageName, R.layout.widget_holiday)

        PatroWidgetViews.tint(views, R.id.widget_bg, colors.background)
        PatroWidgetViews.tint(views, R.id.holiday_divider, PatroWidgetViews.withAlpha(colors.ink, 0.14f))
        views.setTextColor(R.id.holiday_count, colors.holiday)
        views.setTextColor(R.id.holiday_unit, dim)
        views.setTextColor(R.id.holiday_caption, dim)
        views.setTextColor(R.id.holiday_name, colors.ink)
        views.setTextColor(R.id.holiday_date, dim)
        views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openAppIntent(context))
        views.setViewVisibility(R.id.holiday_unit, View.VISIBLE)
        views.setTextViewTextSize(R.id.holiday_count, TypedValue.COMPLEX_UNIT_SP, 30f)

        val holiday = snapshot?.nextHoliday()
        if (snapshot == null || holiday == null) {
            views.setTextViewText(R.id.holiday_count, "–")
            views.setViewVisibility(R.id.holiday_unit, View.GONE)
            views.setTextViewText(R.id.holiday_caption, context.getString(R.string.widget_next_holiday))
            views.setTextViewText(
                R.id.holiday_name,
                context.getString(if (snapshot == null) R.string.widget_open_app_hint else R.string.widget_no_holiday),
            )
            views.setTextViewText(R.id.holiday_date, "")
            return views
        }

        val days = PatroDates.daysBetween(PatroDates.todayKey(), holiday.ad)
        if (days <= 0) {
            views.setTextViewText(R.id.holiday_count, context.getString(R.string.widget_today_word))
            views.setTextViewTextSize(R.id.holiday_count, TypedValue.COMPLEX_UNIT_SP, 18f)
            views.setViewVisibility(R.id.holiday_unit, View.GONE)
            views.setTextViewText(R.id.holiday_caption, context.getString(R.string.widget_holiday_today))
        } else {
            views.setTextViewText(R.id.holiday_count, snapshot.digits(days))
            views.setTextViewText(R.id.holiday_unit, context.resources.getQuantityString(R.plurals.widget_days, days))
            views.setTextViewText(R.id.holiday_caption, context.getString(R.string.widget_next_holiday))
        }
        views.setTextViewText(
            R.id.holiday_name,
            holiday.holidayName ?: context.getString(R.string.widget_public_holiday),
        )
        views.setTextViewText(
            R.id.holiday_date,
            "${snapshot.weekdays[holiday.weekday - 1]}, ${snapshot.shortDate(holiday)} · ${PatroDates.adShort(holiday.ad)}",
        )
        views.setOnClickPendingIntent(R.id.widget_root, PatroWidgetViews.openDayIntent(context, holiday.ad))
        return views
    }
}
