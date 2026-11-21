package app.yawmi.journal

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.util.SizeF
import org.json.JSONObject
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.min
import kotlin.math.sqrt

internal class WidgetSpace(size: SizeF, val layout: JSONObject) {
    val width = size.width.coerceIn(48f, 800f)
    val height = size.height.coerceIn(48f, 900f)
    val slim = height < 105
    val narrow = width < 118
    val clock = layout.optBoolean("clock") && height >= 98
    val heading = !clock && !slim && layout.optBoolean("header", true)
    val toolbar = (clock || !slim) && layout.optBoolean("showSettings", true) && width >= if (clock) 260 else 122
    val refresh = (clock || !slim) && layout.optBoolean("showRefresh", true) && width >= if (clock) 350 else 177
    val header = clock || heading || toolbar || refresh
    val toolsWidth = (if (toolbar) 48f else 0f) + (if (refresh) 48f else 0f)
    val shortcut = layout.optJSONObject("shortcut")?.takeIf {
        it.optString("label").isNotBlank() && it.optString("route").isNotBlank()
    }
    val footer = height >= 170 && !narrow && shortcut != null
    val gap = 6f
    val inset = if (slim || layout.optBoolean("compact")) 6f else 8f
    val outerCorner = min(
        if (!layout.optBoolean("softCorners", true)) 12f else if (narrow || slim) 18f else 26f,
        min(width, height) * .27f,
    )
    fun panelCorner(box: RectF, extraInset: Float = 0f) =
        min(maxOf(4f, outerCorner - inset - extraInset), min(box.width(), box.height()) * .29f)
    val clockDate = layout.optBoolean("clockDate", true)
    val stackedClock = clockDate && width < 146
    val fullDate = clockDate && width >= 210
    val clockSize = if (stackedClock) 20f else if (width < 190) 24f else 29f
    val headerHeight = if (!header) 0f else if (clock) {
        if (narrow) 47f else 50f
    } else if (narrow) 31f else 48f
    val top = inset + headerHeight
    val bottom = inset + if (footer) 54f else 0f
    val contentHeight = height - top - bottom
    private val columns = min(layout.optInt("columns", 3).coerceIn(1, 3),
        ((width - 2 * inset + gap) / 95).toInt().coerceIn(1, 3))
    private val rows = ((contentHeight + gap) / 54).toInt().coerceIn(1, 8)
    val chunks: List<List<JSONObject>> = buildList {
        val cards = layout.optJSONArray("cards") ?: return@buildList
        var index = 0
        repeat(rows) { row ->
            if (index < cards.length()) {
                val first = row == 0 && rows > 1 && columns > 1 &&
                    cards.length() > 1 && layout.optBoolean("featured")
                val count = min(if (first) 1 else columns, cards.length() - index)
                add(List(count) { cards.getJSONObject(index++) })
            }
        }
    }

    fun cell(row: Int, column: Int): RectF {
        val count = chunks[row].size
        val w = (width - 2 * inset - gap * (count - 1)) / count
        val h = (contentHeight - gap * (chunks.size - 1)) / chunks.size
        val x = inset + column * (w + gap)
        val y = top + row * (h + gap)
        return RectF(x, y, x + w, y + h)
    }

    fun footerBox() = RectF(inset, height - bottom + gap, width - inset, height - inset)

    fun clockFrame(ar: Boolean): ClockFrame {
        val outer = RectF(inset + if (ar) toolsWidth else 0f, inset,
            width - inset - if (ar) 0f else toolsWidth, top - gap)
        if (!clockDate) return ClockFrame(outer, outer, null)
        if (stackedClock) {
            val date = RectF(outer).apply { top = bottom - 16 }
            return ClockFrame(outer, RectF(outer).apply { bottom = date.top }, date)
        }
        val timeWidth = (outer.width() * .46f).coerceIn(64f, 142f)
        val time = RectF(outer).apply { if (ar) left = right - timeWidth else right = left + timeWidth }
        val date = RectF(outer).apply { if (ar) right = time.left - gap else left = time.right + gap }
        return ClockFrame(outer, time, date)
    }

    fun toolsBox(ar: Boolean) = if (ar) {
        RectF(inset, inset, inset + toolsWidth, inset + 48)
    } else {
        RectF(width - inset - toolsWidth, inset, width - inset, inset + 48)
    }
}

internal data class ClockFrame(val outer: RectF, val time: RectF, val date: RectF?)

internal data class WidgetDate(val arabic: Boolean, val weekday: String, val line: String)

internal fun widgetDate(space: WidgetSpace, ar: Boolean, day: LocalDate = LocalDate.now()): WidgetDate {
    val arabic = space.layout.optString("clockLanguage", if (ar) "ar" else "en") == "ar"
    val locale = if (arabic) Locale.forLanguageTag("ar-EG") else Locale.ENGLISH
    val weekday = day.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
    val month = day.month.getDisplayName(if (space.fullDate) TextStyle.FULL else TextStyle.SHORT, locale)
    return WidgetDate(arabic, weekday, if (arabic) "${day.dayOfMonth} $month" else "$month ${day.dayOfMonth}")
}

internal class WidgetArtwork(
    private val space: WidgetSpace,
    private val ar: Boolean,
    private val dark: Boolean,
    assets: AssetManager,
) {
    private val style = space.layout.optInt("style", 1)
    private val accent = space.layout.optInt("accent", 0xff315f55.toInt())
    private val navy = 0xff152944.toInt()
    private val cream = 0xfff7f6ee.toInt()
    private val ink = if (dark) cream else navy
    private val base = when (style) {
        0 -> if (dark) 0xff18302b.toInt() else 0xffe7f0e8.toInt()
        2 -> if (dark) 0xff141e33.toInt() else 0xffe2ebf8.toInt()
        3 -> if (dark) 0xff282a32.toInt() else 0xfffcf9ef.toInt()
        4 -> mix(if (dark) 0xff192926.toInt() else Color.WHITE, accent, if (dark) .30f else .19f)
        else -> if (dark) 0xff182d29.toInt() else 0xfff3f0e5.toInt()
    }
    private val button = if (dark) mix(accent, 0xffe1f1da.toInt(), .78f)
        else mix(accent, 0xff18382f.toInt(), .68f)

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val type = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val bold = loadFont(assets, "Tajawal-Bold.ttf", Typeface.DEFAULT_BOLD)
    private val regular = loadFont(assets, "Tajawal-Regular.ttf", Typeface.DEFAULT)

    fun bitmap(density: Float, day: LocalDate): Bitmap {
        val w = space.width
        val h = space.height
        // RemoteViews carries multiple variants on some launchers. Cap each independent bitmap.
        val scale = min(density.coerceIn(1f, 2.15f), sqrt(220_000f / (w * h)))
        val bitmap = Bitmap.createBitmap((w * scale).toInt(), (h * scale).toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        val opacity = space.layout.optDouble("opacity", 1.0).takeIf { it.isFinite() }
            ?.coerceIn(.92, 1.0)?.toFloat() ?: 1f
        val bounds = RectF(0f, 0f, w, h)
        canvas.save()
        canvas.clipPath(Path().apply { addRoundRect(bounds, space.outerCorner, space.outerCorner, Path.Direction.CW) })
        panel(canvas, bounds, alpha(base, opacity), space.outerCorner)
        if (space.clock) {
            drawClock(canvas, day)
        } else if (space.heading) {
            val title = space.layout.optString("heading").ifBlank { if (ar) "يومي" else "Yawmi" }
            val area = RectF(space.inset + 5, space.inset, w - space.inset - 5, space.top)
            if (ar) area.left += space.toolsWidth else area.right -= space.toolsWidth
            text(canvas, title, area, if (space.narrow) 13f else 19f, ink, true, middle = true)
        }
        if (space.toolbar || space.refresh) drawTools(canvas)
        for ((r, row) in space.chunks.withIndex()) {
            for ((c, card) in row.withIndex()) {
                drawCard(canvas, space.cell(r, if (ar) row.lastIndex - c else c), card)
            }
        }
        if (space.chunks.isEmpty() && !space.clock) {
            val area = RectF(space.inset, space.top, w - space.inset, h - space.bottom)
            text(canvas, if (ar) "اختار متابعاتك" else "Choose your trackers", area, 12f, ink, middle = true)
        }
        if (space.footer) drawFooter(canvas)
        canvas.restore()
        return bitmap
    }

    private fun drawClock(canvas: Canvas, day: LocalDate) {
        val panes = space.clockFrame(ar)
        val level = alpha(ink, .08f)
        val timeFill = mix(base, 0xffd6eaa0.toInt(), if (dark) .13f else .28f)
        if (space.stackedClock) {
            panel(canvas, panes.outer, timeFill, space.panelCorner(panes.outer))
        } else {
            panel(canvas, panes.time, timeFill, space.panelCorner(panes.time))
            panes.date?.let { panel(canvas, it, level, space.panelCorner(it)) }
        }
        val dateArea = panes.date ?: return
        val words = widgetDate(space, ar, day)
        if (!space.fullDate) {
            text(canvas, words.line, RectF(dateArea).apply { inset(5f, 0f) }, 11f, ink,
                strong = true, middle = true, rtl = words.arabic, center = true)
            return
        }
        val x = if (words.arabic) dateArea.right - 21 else dateArea.left + 21
        val y = dateArea.centerY()
        val iconBox = RectF(x - 13, y - 13, x + 13, y + 13)
        panel(canvas, iconBox, alpha(ink, .11f), space.panelCorner(iconBox, 5f))
        glyph(canvas, "calendar", x, y, 7f, ink)
        val line = RectF(dateArea).apply {
            inset(8f, 0f)
            if (words.arabic) right -= 33 else left += 33
        }
        text(canvas, words.weekday, RectF(line).apply { top = y - 13; bottom = y }, 10f,
            mix(ink, base, .20f), rtl = words.arabic)
        text(canvas, words.line, RectF(line).apply { top = y - 1; bottom = y + 15 }, 14f, ink,
            strong = true, rtl = words.arabic)
    }

    private fun drawTools(canvas: Canvas) {
        val area = space.toolsBox(ar)
        val settingsX = if (ar) area.left + 24 else area.right - 24
        val y = area.centerY()
        fun tool(x: Float, id: String) {
            val box = RectF(x - 15.5f, y - 15.5f, x + 15.5f, y + 15.5f)
            panel(canvas, box, alpha(ink, .10f), space.panelCorner(box, 5f))
            glyph(canvas, id, x, y, 8f, ink)
        }
        if (space.toolbar) tool(settingsX, "settings")
        if (space.refresh) tool(settingsX + if (!space.toolbar) 0 else if (ar) 48 else -48, "refresh")
    }

    private fun drawFooter(canvas: Canvas) {
        val area = space.footerBox()
        val color = if (dark) navy else Color.WHITE
        val route = space.shortcut?.optString("route")
        panel(canvas, area, button, space.panelCorner(area))
        glyph(canvas, if (route == "routine") "clock" else "add",
            if (ar) area.right - 18 else area.left + 18, area.centerY(), 8f, color)
        area.inset(10f, 0f)
        if (ar) area.right -= 24 else area.left += 24
        text(canvas, space.shortcut?.optString("label").orEmpty(), area, 14f, color, true, middle = true)
    }

    private fun drawCard(canvas: Canvas, box: RectF, card: JSONObject) {
        val w = box.width()
        val h = box.height()
        if (w < 10 || h < 18) return
        val id = card.optString("id")
        val tone = card.optInt("accent", accent)
        val wide = w >= 146 && h >= 55
        val compact = h < 61
        val sizable = h >= 74
        val amount = if (style == 3) .23f else if (dark) {
            if (wide) .44f else .32f
        } else if (wide) .91f else .68f
        val fill = mix(base, tone, amount)
        val luminance = Color.luminance(fill) + .05f
        val fg = when {
            luminance >= 4.5f * (Color.luminance(navy) + .05f) -> navy
            Color.luminance(cream) + .05f >= 4.5f * luminance -> cream
            else -> Color.BLACK
        }
        panel(canvas, box, fill, space.panelCorner(box))
        val points = if (!space.layout.optBoolean("artwork", true)) emptyList() else card.optJSONArray("points")?.let { array ->
            List(array.length()) { array.optDouble(it) }.filter { it.isFinite() }
        }.orEmpty()
        val icon = card.optBoolean("icon", true)
        val graph = if (id == "water") points.isNotEmpty() else points.size > 1
        val marker = if (wide) icon || graph else w >= 114 && sizable && (icon || (id == "water" && graph))
        val pad = if (w < 90) 5f else 8f
        val available = RectF(box).apply { inset(pad, 0f) }
        if (marker) {
            val sw = if (wide) min(112f, w * if (w < 200) .34f else .41f) else 24f
            val sh = if (wide) min(if (w < 200) 54f else 84f, h - 12) else sw
            val side = if (ar) available.left else available.right - sw
            val visual = RectF(side, box.centerY() - sh / 2, side + sw, box.centerY() + sh / 2)
            panel(canvas, visual, alpha(fg, .09f), space.panelCorner(visual, 5f))
            if (ar) available.left += sw + pad else available.right -= sw + pad
            if (id == "water" && points.isNotEmpty() || wide && points.size > 1) {
                val graph = RectF(visual).apply { inset(if (wide) 10f else 4f, if (wide) 8f else 4f) }
                signal(canvas, graph, id, points, fg)
            } else if (icon) {
                glyph(canvas, id, visual.centerX(), visual.centerY(), if (wide) 14f else 7f, fg)
            }
        }
        val unit = card.optString("unit")
        val value = card.optString("value")
        val context = card.optString("context").takeIf { h >= 66 && w >= 93 }.orEmpty()
        val labelSize = if (compact || w < 105) 11f else if (w < 160) 12f else 14f
        val separateUnit = unit.isNotBlank() && w < 75 && h >= 52
        val maxValue = (if (h < 43) 15f else if (compact) 19f else if (wide && sizable) 30f else 23f) *
            if (space.layout.optBoolean("largeValues")) 1.14f else 1f
        val valueSize = maxValue.coerceAtMost(h - labelSize - (if (context.isNotBlank() || separateUnit) 17 else 8))
        val labelHeight = labelSize * 1.08f
        val valueHeight = valueSize * 1.05f
        val detail = if (context.isNotBlank()) context else if (separateUnit) unit else ""
        val detailHeight = if (detail.isBlank()) 0f else 11f
        val top = box.centerY() - (labelHeight + valueHeight + detailHeight) / 2
        canvas.save()
        canvas.clipRect(box)
        text(canvas, card.optString("title"), RectF(available.left, top, available.right, top + labelHeight),
            labelSize, fg, true)
        val valueRect = RectF(available.left, top + labelHeight, available.right, top + labelHeight + valueHeight)
        if (!separateUnit && w >= 75 && unit.isNotBlank()) {
            reading(canvas, value, unit, valueRect, valueSize, fg)
        } else {
            text(canvas, value, valueRect, valueSize, fg, true)
        }
        if (detailHeight > 0) {
            text(canvas, detail, RectF(available.left, valueRect.bottom, available.right, valueRect.bottom + detailHeight),
                10f, fg)
        }
        canvas.restore()
    }

    private fun reading(canvas: Canvas, value: String, unit: String, box: RectF, size: Float, fg: Int) {
        type.typeface = regular
        type.textSize = 10f
        val unitWidth = type.measureText(unit).coerceAtMost(box.width() * .46f)
        type.typeface = bold
        type.textSize = size
        val valueWidth = type.measureText(value).coerceAtMost(box.width() - unitWidth - 4)
        val readingBox = RectF(box)
        val unitBox = RectF(box).apply { top = bottom - 12f }
        if (ar) {
            readingBox.left = box.right - valueWidth - .5f
            unitBox.right = readingBox.left - 4
            unitBox.left = unitBox.right - unitWidth - .5f
        } else {
            readingBox.right = box.left + valueWidth + .5f
            unitBox.left = readingBox.right + 4
            unitBox.right = unitBox.left + unitWidth + .5f
        }
        text(canvas, value, readingBox, size, fg, true)
        text(canvas, unit, unitBox, 10f, fg)
    }

    private fun signal(canvas: Canvas, box: RectF, id: String, values: List<Double>, color: Int) {
        if (id == "water") {
            val r = min(19f, min(box.width(), box.height()) / 2 - 2)
            if (r <= 0) return
            val bounds = RectF(box.centerX() - r, box.centerY() - r, box.centerX() + r, box.centerY() + r)
            stroke(alpha(color, .22f), min(4f, r / 2))
            canvas.drawOval(bounds, paint)
            paint.color = color
            canvas.drawArc(bounds, -90f, (values.first().coerceIn(0.0, 1.0) * 360).toFloat(), false, paint)
            if (r >= 11) glyph(canvas, "water", box.centerX(), box.centerY(), 7f, color)
            return
        }
        val lo = values.min()
        val hi = values.max()
        val span = (hi - lo).coerceAtLeast(.001)
        for (f in listOf(.20f, .50f, .80f)) {
            val y = box.top + box.height() * f
            line(canvas, box.left, y, box.right, y, alpha(color, .23f), 1f)
        }
        val plot = Path()
        val coords = values.mapIndexed { i, number ->
            val x = box.left + box.width() * i / values.lastIndex
            val y = if (hi == lo) box.centerY() else
                box.bottom - box.height() * (.16f + .68f * ((number - lo) / span).toFloat())
            if (i == 0) plot.moveTo(x, y) else plot.lineTo(x, y)
            x to y
        }
        stroke(color, 2f)
        canvas.drawPath(plot, paint)
        paint.style = Paint.Style.FILL
        for ((x, y) in listOf(coords.first(), coords.last())) canvas.drawCircle(x, y, 2.5f, paint)
    }

    private fun glyph(canvas: Canvas, id: String, x: Float, y: Float, r: Float, color: Int) {
        canvas.save()
        canvas.translate(x, y)
        val scale = r / 8f
        canvas.scale(scale, scale)
        stroke(color, 1.55f)
        val path = Path()
        when (id) {
            "water", "glucose" -> {
                path.moveTo(0f, -7f)
                path.cubicTo(-2f, -4f, -6f, 0f, -6f, 3f)
                path.cubicTo(-6f, 10f, 6f, 10f, 6f, 3f)
                path.cubicTo(6f, 0f, 2f, -4f, 0f, -7f)
                if (id == "glucose") {
                    path.moveTo(-5f, 3f); path.lineTo(5f, 3f)
                }
            }
            "medicine" -> {
                canvas.rotate(45f)
                canvas.drawRoundRect(-4f, -8f, 4f, 8f, 4f, 4f, paint)
                path.moveTo(-4f, 0f); path.lineTo(4f, 0f)
            }
            "settings" -> {
                path.moveTo(-7f, -3f); path.lineTo(7f, -3f)
                path.moveTo(-7f, 3f); path.lineTo(7f, 3f)
                canvas.drawCircle(-2f, -3f, 2f, paint); canvas.drawCircle(2f, 3f, 2f, paint)
            }
            "refresh" -> {
                canvas.drawArc(RectF(-6.5f, -6.5f, 6.5f, 6.5f), -42f, 286f, false, paint)
                path.moveTo(6.5f, -7f); path.lineTo(6.5f, -2.5f); path.lineTo(2f, -2.5f)
            }
            "add" -> {
                path.moveTo(-6f, 0f); path.lineTo(6f, 0f)
                path.moveTo(0f, -6f); path.lineTo(0f, 6f)
            }
            "clock" -> {
                canvas.drawCircle(0f, 0f, 7f, paint)
                path.moveTo(0f, -4f); path.lineTo(0f, 0f); path.lineTo(3f, 2f)
            }
            "calendar" -> {
                canvas.drawRoundRect(-7f, -6f, 7f, 7f, 2f, 2f, paint)
                path.moveTo(-7f, -2f); path.lineTo(7f, -2f)
                path.moveTo(-3f, -8f); path.lineTo(-3f, -4f)
                path.moveTo(3f, -8f); path.lineTo(3f, -4f)
            }
            "sleep" -> {
                path.moveTo(3f, -7f)
                path.cubicTo(-6f, -9f, -10f, 4f, -2f, 7f)
                path.cubicTo(2f, 9f, 6f, 6f, 7f, 3f)
                path.cubicTo(2f, 5f, -1f, 0f, 3f, -7f)
            }
            "pulse", "pressure", "oxygen" -> {
                path.moveTo(-8f, 1f); path.lineTo(-4f, 1f); path.lineTo(-1f, -5f)
                path.lineTo(2f, 5f); path.lineTo(5f, 1f); path.lineTo(8f, 1f)
            }
            else -> {
                path.moveTo(-7f, -7f); path.lineTo(-7f, 7f); path.lineTo(7f, 7f)
                path.moveTo(-4f, 3f); path.lineTo(0f, -2f); path.lineTo(3f, 0f); path.lineTo(7f, -5f)
            }
        }
        canvas.drawPath(path, paint)
        canvas.restore()
    }

    private fun line(canvas: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Int, width: Float) {
        stroke(color, width)
        canvas.drawLine(x1, y1, x2, y2, paint)
    }

    private fun stroke(color: Int, width: Float) {
        paint.color = color
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.strokeWidth = width
    }

    private fun panel(canvas: Canvas, box: RectF, color: Int, radius: Float) {
        paint.color = color
        paint.style = Paint.Style.FILL
        canvas.drawRoundRect(box, radius, radius, paint)
    }

    private fun text(canvas: Canvas, value: String, box: RectF, size: Float, color: Int,
                     strong: Boolean = false, middle: Boolean = false,
                     rtl: Boolean = ar, center: Boolean = false) {
        val width = box.width().toInt()
        if (value.isBlank() || width < 6) return
        type.color = color
        type.typeface = if (strong) bold else regular
        type.textSize = size.coerceAtLeast(8f)
        val required = type.measureText(value)
        if (required > width) type.textSize = (type.textSize * width / required).coerceAtLeast(9f)
        val paragraph = StaticLayout.Builder.obtain(value, 0, value.length, type, width)
            .setAlignment(if (center) Layout.Alignment.ALIGN_CENTER else Layout.Alignment.ALIGN_NORMAL)
            .setTextDirection(if (rtl) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR)
            .setIncludePad(false)
            .setMaxLines(1)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()
        canvas.save()
        canvas.translate(box.left, if (middle) box.centerY() - paragraph.height / 2f else box.top)
        paragraph.draw(canvas)
        canvas.restore()
    }

    private fun mix(a: Int, b: Int, p: Float) = Color.rgb(
        (Color.red(a) + p * (Color.red(b) - Color.red(a))).toInt(),
        (Color.green(a) + p * (Color.green(b) - Color.green(a))).toInt(),
        (Color.blue(a) + p * (Color.blue(b) - Color.blue(a))).toInt(),
    )

    private fun alpha(color: Int, amount: Float) = Color.argb(
        (255 * amount).toInt(), Color.red(color), Color.green(color), Color.blue(color),
    )

    companion object {
        private val fonts = mutableMapOf<String, Typeface>()

        @Synchronized
        private fun loadFont(assets: AssetManager, name: String, fallback: Typeface): Typeface =
            fonts.getOrPut(name) {
                runCatching { Typeface.createFromAsset(assets, "flutter_assets/assets/$name") }
                    .getOrDefault(fallback)
            }
    }
}
