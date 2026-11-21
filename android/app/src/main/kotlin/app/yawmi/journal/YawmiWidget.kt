package app.yawmi.journal

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.util.Log
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.ZonedDateTime
import org.json.JSONArray
import java.util.UUID
import kotlin.math.roundToInt

@Synchronized
internal fun shortcutToken(context: Context): String {
    val store = context.getSharedPreferences("yawmi_shortcuts", Context.MODE_PRIVATE)
    return store.getString("entry", null) ?: UUID.randomUUID().toString().also {
        store.edit().putString("entry", it).apply()
    }
}

internal fun appShortcut(context: Context, route: String, key: String): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).setAction("app.yawmi.OPEN")
        .setData(Uri.Builder().scheme("yawmi").authority("open").appendPath(key).build())
        .putExtra("route", route).putExtra("token", shortcutToken(context))
        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
}

open class YawmiWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle) {
        update(context, manager, id, newOptions)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = store(context).edit()
        ids.forEach { edit.remove(it.toString()) }
        edit.apply()
    }

    companion object {
        private const val automatic = "today"
        private const val snapshotKey = "snapshot_v2"
        private val providers = listOf(
            YawmiWidget::class.java, YawmiStripWidget::class.java, YawmiTowerWidget::class.java,
            YawmiBoardWidget::class.java, YawmiSquareWidget::class.java, YawmiMatrixWidget::class.java,
            YawmiPortraitWidget::class.java, YawmiGridWidget::class.java,
        )

        fun component(context: Context) = ComponentName(context, YawmiWidget::class.java)

        fun owns(context: Context, manager: AppWidgetManager, id: Int): Boolean =
            providers.any { manager.getAppWidgetInfo(id)?.provider == ComponentName(context, it) }

        private fun store(context: Context) =
            context.getSharedPreferences("yawmi_widgets", Context.MODE_PRIVATE)

        private fun snapshot(context: Context) = runCatching {
            JSONObject(store(context).getString(snapshotKey, "{}") ?: "{}")
        }.getOrDefault(JSONObject())

        fun usedLayouts(context: Context): Set<String> = store(context).all
            .filterKeys { it.toIntOrNull() != null }.values.filterIsInstance<String>().toSet()

        fun installedIds(context: Context): List<Int> {
            val manager = AppWidgetManager.getInstance(context)
            return providers.flatMap { manager.getAppWidgetIds(ComponentName(context, it)).toList() }.sorted()
        }

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (provider in providers) {
                manager.getAppWidgetIds(ComponentName(context, provider)).forEach {
                    update(context, manager, it)
                }
            }
        }

        fun activeLayout(context: Context, id: Int): Map<String, Any>? {
            val manager = AppWidgetManager.getInstance(context)
            if (!owns(context, manager, id)) return null
            val state = snapshot(context)
            val layouts = state.optJSONObject("layouts") ?: JSONObject()
            val key = resolve(context, id, state, layouts)
            val instance = store(context).getString(id.toString(), null)
            val shared = key == state.optString("default") || store(context).all
                .any { (slot, value) -> slot.toIntOrNull() != null && slot != id.toString() && value == key }
            val options = manager.getAppWidgetOptions(id)
            val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            val widthKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
                else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH
            val heightKey = if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
                else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
            val width = options.getInt(widthKey, 330).toFloat()
            val height = options.getInt(heightKey, 240).toFloat()
            val selected = reportedSizes(options).minByOrNull {
                kotlin.math.abs(it.width - width) + kotlin.math.abs(it.height - height)
            }
            return mapOf("key" to key, "editable" to (key != automatic && instance == key && !shared),
                "width" to (selected?.width ?: width).toDouble(),
                "height" to (selected?.height ?: height).toDouble())
        }

        private fun reportedSizes(options: Bundle): List<SizeF> {
            if (Build.VERSION.SDK_INT < 31) return emptyList()
            @Suppress("DEPRECATION")
            return options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                ?.filter { it.width.isFinite() && it.height.isFinite() && it.width > 0 && it.height > 0 }
                ?.distinct()?.sortedBy { it.width * it.height }.orEmpty()
        }

        private fun resolve(context: Context, id: Int, state: JSONObject, layouts: JSONObject): String {
            val bound = store(context).getString(id.toString(), null)
            if (bound != null && layouts.has(bound)) return bound
            return state.optString("default", automatic).takeIf(layouts::has) ?: automatic
        }

        fun publish(context: Context, raw: String, widgetId: Int?, key: String?) {
            val layouts = JSONObject(raw).getJSONObject("layouts")
            require(layouts.has(automatic))
            val manager = AppWidgetManager.getInstance(context)
            val edit = store(context).edit().putString(snapshotKey, raw)
            if (widgetId != null && key != null) {
                require(owns(context, manager, widgetId) && layouts.has(key))
                edit.putString(widgetId.toString(), key)
            }
            check(edit.commit())
            var targetSucceeded = widgetId == null
            var allSucceeded = true
            for (provider in providers) {
                for (id in manager.getAppWidgetIds(ComponentName(context, provider))) {
                    val done = update(context, manager, id)
                    allSucceeded = done && allSucceeded
                    if (id == widgetId) targetSucceeded = done
                }
            }
            check(if (widgetId == null) allSucceeded else targetSucceeded)
        }

        fun assign(context: Context, id: Int, key: String): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            if (!owns(context, manager, id)) return false
            val layouts = snapshot(context).optJSONObject("layouts")
            if (key != automatic && layouts?.has(key) != true) return false
            if (!store(context).edit().putString(id.toString(), key).commit()) return false
            return update(context, manager, id)
        }

        fun configure(activity: Activity, id: Int) {
            val manager = AppWidgetManager.getInstance(activity)
            val state = snapshot(activity)
            val layouts = state.optJSONObject("layouts")
            val ar = arabic(activity, state)
            fun finishWith(key: String?) {
                if (if (key == null) update(activity, manager, id) else assign(activity, id, key)) {
                    activity.setResult(Activity.RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
                }
                activity.finish()
            }
            if (layouts == null || layouts.length() < 2) {
                finishWith(null)
                return
            }
            val keys = layouts.keys().asSequence().toList()
            AlertDialog.Builder(activity)
                .setTitle(if (ar) "اختار محتوى الويدجت" else "Choose widget content")
                .setItems(keys.map { layouts.optJSONObject(it)?.optString("name").orEmpty() }.toTypedArray()) {
                    _, index -> finishWith(keys[index])
                }
                .setOnCancelListener { activity.finish() }
                .show()
        }

        private fun arabic(context: Context, state: JSONObject): Boolean =
            state.optBoolean("ar", context.resources.configuration.locales[0].language == "ar")

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            options: Bundle = manager.getAppWidgetOptions(id),
        ): Boolean = runCatching { draw(context, manager, id, options) }.onFailure {
            Log.w("YawmiWidget", "Widget update failed: " + it.javaClass.simpleName)
        }.isSuccess

        private fun draw(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
            val state = snapshot(context)
            val ar = arabic(context, state)
            val layouts = state.optJSONObject("layouts")
            val stored = layouts?.optJSONObject(resolve(context, id, state, layouts))
            val layout = stored?.let { currentLayout(it, state, ar, ZonedDateTime.now()) }
            val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
            val info = manager.getAppWidgetInfo(id)
            val w = (info?.minWidth?.div(density) ?: 170f).roundToInt()
            val h = (info?.minHeight?.div(density) ?: 110f).roundToInt()
            fun dp(key: String, fallback: Int) = options.getInt(key, fallback).toFloat().coerceAtLeast(48f)
            val portrait = SizeF(dp(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, w),
                dp(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, h))
            val landscape = SizeF(dp(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, w),
                dp(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, h))
            fun at(size: SizeF) = art(context, id, layout, size, ar)
            if (Build.VERSION.SDK_INT >= 31) {
                val sizes = reportedSizes(options)
                if (sizes.isNotEmpty()) {
                    val variants = if (sizes.size <= 4) sizes
                        else listOf(sizes.first(), sizes[sizes.size / 3], sizes[sizes.size * 2 / 3], sizes.last())
                    if (variants.size == 1) {
                        manager.updateAppWidget(id, at(variants.first()))
                        return
                    }
                    if (runCatching { manager.updateAppWidget(id, RemoteViews(variants.associateWith(::at))) }.isSuccess)
                        return
                    manager.updateAppWidget(id, at(variants.first()))
                    return
                }
            }
            if (portrait != landscape &&
                options.containsKey(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH) &&
                options.containsKey(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)) {
                if (runCatching { manager.updateAppWidget(id, RemoteViews(at(landscape), at(portrait))) }.isSuccess)
                    return
            }
            manager.updateAppWidget(id, at(portrait))
        }

        private fun currentLayout(layout: JSONObject, source: JSONObject, ar: Boolean, now: ZonedDateTime): JSONObject {
            val date = now.toLocalDate().toString()
            val offset = now.offset.totalSeconds / 60
            if (source.optString("day") == date && source.optInt("offset", offset) == offset) return layout
            val cards = layout.optJSONArray("cards") ?: return layout
            val updated = JSONArray()
            for (i in 0 until cards.length()) {
                val card = cards.getJSONObject(i)
                if (!card.optBoolean("daily")) {
                    updated.put(card)
                    continue
                }
                val current = JSONObject(card.toString()).apply { remove("advance"); remove("points") }
                val next = card.optJSONObject("advance")?.optJSONObject(date)
                    ?.takeIf { it.optInt("offset", Int.MIN_VALUE) == offset }
                if (next != null) {
                    next.keys().forEach { key -> if (key != "offset") current.put(key, next.get(key)) }
                } else {
                    val hidden = card.optString("value").startsWith("•")
                    if (!hidden) current.put("value", "—")
                    current.put("unit", "")
                    current.put("context", if (ar) "افتح يومي لتحديث البيانات" else "Open Yawmi to update")
                    current.put("route", if (card.optString("id") == "medicine") "routine" else "today")
                }
                updated.put(current)
            }
            return JSONObject(layout.toString()).put("cards", updated)
        }

        private fun art(context: Context, id: Int, layout: JSONObject?, size: SizeF, ar: Boolean): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.yawmi_widget)
            val studio = "studio/$id"
            val launcherDark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
            val dark = when (layout?.optString("appearance")) {
                "light" -> false
                "dark" -> true
                else -> launcherDark
            }
            val space = layout?.let { WidgetSpace(size, it) }
            val visible = space != null
            val empty = when {
                layout == null -> if (ar) "يومي · افتح التطبيق مرة واحدة" else "Yawmi · Open the app to sync"
                else -> if (ar) "يومي · اختار متابعاتك" else "Yawmi · Choose your trackers"
            }
            views.setTextViewText(R.id.widget_fallback_text, empty)
            views.setOnClickPendingIntent(R.id.widget_fallback_text,
                appShortcut(context, studio, "widget-setup-$id"))
            views.setViewVisibility(R.id.widget_fallback_text, if (visible) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_image, if (visible) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_buttons, if (visible) View.VISIBLE else View.GONE)
            val clock = space?.clock == true && visible
            views.setViewVisibility(R.id.widget_clock_strip, if (clock) View.VISIBLE else View.GONE)
            if (!visible || space == null) return views
            val density = context.resources.displayMetrics.density
            fun px(dp: Float) = (dp * density).roundToInt().coerceAtLeast(0)
            if (clock) {
                val time = R.id.widget_clock_time
                val color = if (dark) 0xfff7f6ee.toInt() else 0xff152944.toInt()
                val format = space.layout.optString("clockFormat", "system")
                val twelve: CharSequence = if (space.width < 190) "h:mm" else SpannableString("h:mm a").apply {
                    setSpan(RelativeSizeSpan(.48f), length - 1, length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
                }
                views.setCharSequence(time, "setFormat12Hour", if (format == "24") "HH:mm" else twelve)
                views.setCharSequence(time, "setFormat24Hour", if (format == "12") twelve else "HH:mm")
                views.setTextColor(time, color)
                views.setTextViewTextSize(time, TypedValue.COMPLEX_UNIT_DIP, space.clockSize)
                val frame = space.clockFrame(ar).time
                views.setViewPadding(R.id.widget_clock_strip, px(frame.left + 3),
                    px(frame.centerY() - space.clockSize * .57f), px(space.width - frame.right + 3), 0)
                if (space.clockDate) {
                    val date = widgetDate(space, ar)
                    views.setContentDescription(R.id.widget_clock_strip, "${date.weekday} ${date.line}")
                } else {
                    views.setContentDescription(R.id.widget_clock_strip, null)
                }
                views.setOnClickPendingIntent(R.id.widget_clock_strip, appShortcut(context, "today", "widget-clock-$id"))
            }
            views.setImageViewBitmap(R.id.widget_image, WidgetArtwork(space, ar, dark, context.assets).bitmap(density))
            val edit = appShortcut(context, studio, "widget-studio-$id")
            views.setOnClickPendingIntent(R.id.widget_image, edit)
            views.setViewVisibility(R.id.widget_chrome, View.VISIBLE)
            views.setViewPadding(R.id.widget_chrome, px(space.inset), px(space.inset), px(space.inset), px(space.inset))
            val tools = space.toolbar || space.refresh
            views.setViewVisibility(R.id.widget_tools_left, if (ar && tools) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_tools_right, if (!ar && tools) View.VISIBLE else View.GONE)
            val settings = if (ar) R.id.widget_settings_left else R.id.widget_settings_right
            val refresh = if (ar) R.id.widget_refresh_left else R.id.widget_refresh_right
            views.setViewVisibility(refresh, if (space.refresh) View.VISIBLE else View.GONE)
            views.setViewVisibility(settings, if (space.toolbar) View.VISIBLE else View.GONE)
            views.setContentDescription(settings, if (ar) "إعدادات الويدجت" else "Widget settings")
            views.setOnClickPendingIntent(settings, edit)
            if (space.refresh) {
                val intent = Intent(context, YawmiWidget::class.java).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .setData(Uri.parse("yawmi://widget/refresh/$id"))
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(id))
                views.setContentDescription(refresh, if (ar) "حدّث الويدجت" else "Refresh widget")
                views.setOnClickPendingIntent(refresh, PendingIntent.getBroadcast(context, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            views.setViewVisibility(R.id.widget_shortcut, if (space.footer) View.VISIBLE else View.GONE)
            if (space.footer) space.shortcut?.let { shortcut ->
                views.setContentDescription(R.id.widget_shortcut, shortcut.getString("label"))
                views.setOnClickPendingIntent(R.id.widget_shortcut,
                    appShortcut(context, shortcut.getString("route"), "widget-action-$id"))
            }
            views.setViewPadding(R.id.widget_buttons, px(space.inset), px(space.top), px(space.inset), px(space.bottom))
            views.removeAllViews(R.id.widget_buttons)
            fun gap() = RemoteViews(context.packageName, R.layout.yawmi_widget_gap)
            for ((r, cards) in space.chunks.withIndex()) {
                if (r > 0) views.addView(R.id.widget_buttons, gap())
                val line = RemoteViews(context.packageName, R.layout.yawmi_widget_row)
                for ((c, card) in (if (ar) cards.reversed() else cards).withIndex()) {
                    if (c > 0) line.addView(R.id.widget_row, gap())
                    val cell = RemoteViews(context.packageName, R.layout.yawmi_widget_cell)
                    val label = listOf(card.optString("title"), card.optString("value"),
                        card.optString("unit"), card.optString("context"))
                        .filter { it.isNotBlank() }.joinToString(" ")
                    cell.setContentDescription(R.id.widget_hit, label)
                    val route = card.optString("route", studio)
                    cell.setOnClickPendingIntent(R.id.widget_hit, appShortcut(context, route, "widget-$id-$r-$c"))
                    line.addView(R.id.widget_row, cell)
                }
                views.addView(R.id.widget_buttons, line)
            }
            return views
        }
    }
}

class YawmiStripWidget : YawmiWidget()
class YawmiTowerWidget : YawmiWidget()
class YawmiBoardWidget : YawmiWidget()
class YawmiSquareWidget : YawmiWidget()
class YawmiMatrixWidget : YawmiWidget()
class YawmiPortraitWidget : YawmiWidget()
class YawmiGridWidget : YawmiWidget()

class WidgetPinned : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val layout = intent.getStringExtra("layout") ?: return
        if (id != AppWidgetManager.INVALID_APPWIDGET_ID) YawmiWidget.assign(context, id, layout)
    }
}

class WidgetConfiguration : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val manager = AppWidgetManager.getInstance(this)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID || !YawmiWidget.owns(this, manager, id)) {
            finish()
            return
        }
        YawmiWidget.configure(this, id)
    }
}
