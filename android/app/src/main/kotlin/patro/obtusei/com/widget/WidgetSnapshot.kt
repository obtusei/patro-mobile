package patro.obtusei.com.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** A festival, holiday or user event shown under a day. */
class WidgetEntry(
    val title: String,
    /** Start time of a timed user event, already formatted. */
    val time: String?,
    val color: Int?,
    val isHoliday: Boolean,
) {
    val label: String get() = if (time == null) title else "$time  $title"
}

/** One calendar day, as published by lib/providers/widget_sync_provider.dart. */
class WidgetDay(
    /** Gregorian date as yyyy-MM-dd. */
    val ad: String,
    val year: Int,
    val month: Int,
    val day: Int,
    /** 1 = Sunday … 7 = Saturday. */
    val weekday: Int,
    val tithi: String?,
    val isPublicHoliday: Boolean,
    /** One of the weekly days off picked in Settings (Saturday by default). */
    val isWeekend: Boolean,
    val entries: List<WidgetEntry>,
    /** Published separately for when festivals are hidden from [entries]. */
    private val holidayNameHint: String? = null,
) {
    val isRestDay: Boolean get() = isWeekend || isPublicHoliday
    val holidayName: String? get() = entries.firstOrNull { it.isHoliday }?.title ?: holidayNameHint
    val monthKey: Int get() = year * 12 + month - 1
    val adDay: Int get() = ad.substring(8).toInt()
}

class WidgetColors(
    val background: Int,
    val surface: Int,
    val ink: Int,
    val accent: Int,
    val highlight: Int,
    val holiday: Int,
) {
    companion object {
        /** The app's default "Obsidian" preset, used before the first publish. */
        val DEFAULT = WidgetColors(
            background = 0xFF121214.toInt(),
            surface = 0xFF1B1B1F.toInt(),
            ink = 0xFFEFECE6.toInt(),
            accent = 0xFFFFD700.toInt(),
            highlight = 0xFF4A80F0.toInt(),
            holiday = 0xFFFF6E61.toInt(),
        )

        fun fromJson(json: JSONObject?): WidgetColors {
            if (json == null) return DEFAULT
            fun read(key: String, fallback: Int) =
                if (json.has(key)) json.getLong(key).toInt() else fallback
            return WidgetColors(
                background = read("background", DEFAULT.background),
                surface = read("surface", DEFAULT.surface),
                ink = read("ink", DEFAULT.ink),
                accent = read("accent", DEFAULT.accent),
                highlight = read("highlight", DEFAULT.highlight),
                holiday = read("holiday", DEFAULT.holiday),
            )
        }
    }
}

class WidgetSnapshot(
    val sticky: Boolean,
    /** The notification's status-bar icon is today's date, not the Patro mark. */
    val statusBarDate: Boolean,
    /** Status-bar date: BS in Devanagari numerals when true, AD otherwise. */
    val statusBarBs: Boolean,
    val nepaliDigits: Boolean,
    val weekStartsMonday: Boolean,
    /** Weekly days off, 1 = Sunday … 7 = Saturday. */
    val weekendDays: Set<Int>,
    val colors: WidgetColors,
    /** BS month names, Baishakh first. */
    val months: List<String>,
    /** Indexed by [WidgetDay.weekday] - 1. */
    val weekdays: List<String>,
    val weekdaysShort: List<String>,
    /** Consecutive days, oldest first, covering whole BS months. */
    val days: List<WidgetDay>,
) {
    private val indexByAd = days.withIndex().associate { (i, day) -> day.ad to i }
    private val byMonth = days.groupBy { it.monthKey }

    /** BS months available to page through, oldest first. */
    val monthKeys: List<Int> = byMonth.keys.sorted()

    fun dayOn(ad: String): WidgetDay? = indexByAd[ad]?.let { days[it] }
    fun today(): WidgetDay? = dayOn(PatroDates.todayKey())
    fun daysOf(monthKey: Int): List<WidgetDay> = byMonth[monthKey].orEmpty()

    fun digits(n: Int): String = if (nepaliDigits) PatroDates.devanagari(n.toString()) else n.toString()

    fun monthTitle(day: WidgetDay) = "${months[day.month - 1]} ${digits(day.year)}"

    /** "१४ कात्तिक". */
    fun shortDate(day: WidgetDay) = "${digits(day.day)} ${months[day.month - 1]}"

    /** Today and every published day after it. */
    fun daysFromToday(): List<WidgetDay> {
        val todayKey = PatroDates.todayKey()
        indexByAd[todayKey]?.let { return days.subList(it, days.size) }
        return if (days.isNotEmpty() && todayKey < days.first().ad) days else emptyList()
    }

    /** The first public holiday from today on, not counting weekly days off. */
    fun nextHoliday(): WidgetDay? = daysFromToday().firstOrNull { it.isPublicHoliday }

    /** "१४ कात्तिक २०८३, शनिबार". */
    fun longDate(day: WidgetDay) =
        "${digits(day.day)} ${monthTitle(day)}, ${weekdays[day.weekday - 1]}"

    /** Index into [monthKeys] of the month holding today, or the nearest end if outside. */
    fun currentMonthIndex(): Int {
        today()?.let { return monthKeys.indexOf(it.monthKey) }
        return if (days.isNotEmpty() && PatroDates.todayKey() > days.last().ad) monthKeys.lastIndex else 0
    }

    companion object {
        fun parse(raw: String): WidgetSnapshot {
            val json = JSONObject(raw)
            return WidgetSnapshot(
                sticky = json.optBoolean("sticky", true),
                statusBarDate = json.optBoolean("statusBarDate", true),
                statusBarBs = json.optBoolean("statusBarBs", true),
                nepaliDigits = json.optBoolean("nepaliDigits", true),
                weekStartsMonday = json.optBoolean("weekStartsMonday", false),
                weekendDays = json.optJSONArray("weekendDays")
                    ?.let { arr -> (0 until arr.length()).map { arr.getInt(it) }.toSet() }
                    ?: setOf(7),
                colors = WidgetColors.fromJson(json.optJSONObject("colors")),
                months = json.getJSONArray("months").strings(),
                weekdays = json.getJSONArray("weekdays").strings(),
                weekdaysShort = json.getJSONArray("weekdaysShort").strings(),
                days = json.getJSONArray("days").objects().map(::parseDay),
            )
        }

        private fun parseDay(json: JSONObject) = WidgetDay(
            ad = json.getString("ad"),
            year = json.getInt("y"),
            month = json.getInt("m"),
            day = json.getInt("d"),
            weekday = json.getInt("wd"),
            tithi = json.optString("t").ifEmpty { null },
            isPublicHoliday = json.optBoolean("h"),
            isWeekend = if (json.has("w")) json.optBoolean("w") else json.getInt("wd") == 7,
            entries = json.optJSONArray("e")?.objects()?.map {
                WidgetEntry(
                    title = it.getString("t"),
                    time = it.optString("s").ifEmpty { null },
                    color = if (it.has("c")) it.getLong("c").toInt() else null,
                    isHoliday = it.optBoolean("h"),
                )
            }.orEmpty(),
            holidayNameHint = json.optString("hn").ifEmpty { null },
        )

        private fun JSONArray.strings() = List(length()) { getString(it) }
        private fun JSONArray.objects() = List(length()) { getJSONObject(it) }
    }
}

/** Persists the latest snapshot so widgets can redraw without the app running. */
object WidgetStore {
    private const val PREFS = "patro_widgets"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_ASKED_NOTIFICATIONS = "asked_notifications"

    @Volatile
    private var cache: Pair<String, WidgetSnapshot>? = null

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(context: Context, raw: String) {
        prefs(context).edit().putString(KEY_SNAPSHOT, raw).apply()
    }

    fun load(context: Context): WidgetSnapshot? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        cache?.let { (cachedRaw, snapshot) -> if (cachedRaw == raw) return snapshot }
        return try {
            WidgetSnapshot.parse(raw).also { cache = raw to it }
        } catch (e: Exception) {
            android.util.Log.w("Patro", "Unreadable widget snapshot", e)
            null
        }
    }

    /** The day picked on a month widget, as yyyy-MM-dd. */
    fun monthSelection(context: Context, widgetId: Int): String? =
        prefs(context).getString("month_selected_$widgetId", null)

    fun setMonthSelection(context: Context, widgetId: Int, ad: String) {
        prefs(context).edit().putString("month_selected_$widgetId", ad).apply()
    }

    fun clearMonthSelection(context: Context, widgetId: Int) {
        prefs(context).edit().remove("month_selected_$widgetId").apply()
    }

    fun monthOffset(context: Context, widgetId: Int) =
        prefs(context).getInt("month_offset_$widgetId", 0)

    fun setMonthOffset(context: Context, widgetId: Int, offset: Int) {
        prefs(context).edit().putInt("month_offset_$widgetId", offset).apply()
    }

    fun clearMonthOffset(context: Context, widgetId: Int) {
        prefs(context).edit().remove("month_offset_$widgetId").apply()
    }

    /** Whether the notification permission prompt has been shown once already. */
    fun askedForNotifications(context: Context) = prefs(context).getBoolean(KEY_ASKED_NOTIFICATIONS, false)

    fun markAskedForNotifications(context: Context) {
        prefs(context).edit().putBoolean(KEY_ASKED_NOTIFICATIONS, true).apply()
    }
}

object PatroDates {
    private val devanagariDigits = "०१२३४५६७८९"

    fun devanagari(input: String) = buildString(input.length) {
        for (ch in input) append(if (ch in '0'..'9') devanagariDigits[ch - '0'] else ch)
    }

    /** The device's local date as yyyy-MM-dd, matching [WidgetDay.ad]. */
    fun todayKey(): String {
        val now = Calendar.getInstance()
        return String.format(
            Locale.US, "%04d-%02d-%02d",
            now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH),
        )
    }

    private fun parse(ad: String): Calendar = Calendar.getInstance().apply {
        clear()
        set(ad.substring(0, 4).toInt(), ad.substring(5, 7).toInt() - 1, ad.substring(8, 10).toInt())
    }

    /** Whole days from [from] to [to], both yyyy-MM-dd. */
    fun daysBetween(from: String, to: String): Int {
        val millis = parse(to).timeInMillis - parse(from).timeInMillis
        // Rounded, so a daylight-saving shift in between can't lose a day.
        return Math.round(millis / 86_400_000.0).toInt()
    }

    /** "31 Oct". */
    fun adShort(ad: String): String =
        SimpleDateFormat("d MMM", Locale.ENGLISH).format(parse(ad).time)

    /** "Sat, 31 Oct 2026". */
    fun adLabel(ad: String): String =
        SimpleDateFormat("EEE, d MMM yyyy", Locale.ENGLISH).format(parse(ad).time)

    /** "OCT – NOV 2026": the Gregorian months a BS month straddles. */
    fun adSpan(first: String, last: String): String {
        val month = SimpleDateFormat("MMM", Locale.ENGLISH)
        val start = parse(first)
        val end = parse(last)
        val label = if (start.get(Calendar.YEAR) == end.get(Calendar.YEAR)) {
            "${month.format(start.time)} – ${month.format(end.time)} ${end.get(Calendar.YEAR)}"
        } else {
            "${month.format(start.time)} ${start.get(Calendar.YEAR)} – " +
                "${month.format(end.time)} ${end.get(Calendar.YEAR)}"
        }
        return label.uppercase(Locale.ENGLISH)
    }
}
