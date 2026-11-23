package app.yawmi.journal

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint

private val ReminderKind.icon: Int get() = when (this) {
    ReminderKind.MEDICINE -> R.drawable.ic_notice_dose
    ReminderKind.GLUCOSE -> R.drawable.ic_notice_glucose
    ReminderKind.PRESSURE -> R.drawable.ic_notice_pressure
    ReminderKind.MEASUREMENT -> R.drawable.ic_notice_measurement
    ReminderKind.WATER -> R.drawable.ic_notice_water
    ReminderKind.SLEEP -> R.drawable.ic_notice_sleep
    ReminderKind.FORECAST, ReminderKind.STOCK -> R.drawable.ic_notice_stock
    ReminderKind.EXPIRY -> R.drawable.ic_notice_expiry
    ReminderKind.LAB -> R.drawable.ic_notice_lab
    ReminderKind.VISIT -> R.drawable.ic_notice_visit
    ReminderKind.FOLLOW_UP -> R.drawable.ic_notice_followup
    ReminderKind.TRACKING -> R.drawable.ic_reminder
    ReminderKind.UPDATE -> R.drawable.ic_notice_update
}

private val ReminderKind.accent: Int get() = when (this) {
    ReminderKind.MEDICINE -> 0xFF69439E.toInt()
    ReminderKind.GLUCOSE -> 0xFF9B397D.toInt()
    ReminderKind.PRESSURE -> 0xFFB23B4B.toInt()
    ReminderKind.MEASUREMENT -> 0xFF146D63.toInt()
    ReminderKind.WATER -> 0xFF1769A7.toInt()
    ReminderKind.SLEEP -> 0xFF3E4A90.toInt()
    ReminderKind.STOCK -> 0xFF825600.toInt()
    ReminderKind.FORECAST -> 0xFF9B560C.toInt()
    ReminderKind.EXPIRY -> 0xFFA34B24.toInt()
    ReminderKind.LAB -> 0xFF416622.toInt()
    ReminderKind.VISIT -> 0xFF286655.toInt()
    ReminderKind.FOLLOW_UP -> 0xFF575A71.toInt()
    ReminderKind.TRACKING -> 0xFF4D5662.toInt()
    ReminderKind.UPDATE -> 0xFF00646A.toInt()
}

private fun ReminderKind.badge(context: Context): Bitmap {
    val size = (52 * context.resources.displayMetrics.density).toInt().coerceIn(52, 156)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawCircle(size / 2f, size / 2f, size / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accent })
    context.getDrawable(icon)?.mutate()?.apply {
        setTint(Color.WHITE)
        val inset = size / 5
        setBounds(inset, inset, size - inset, size - inset)
        draw(canvas)
    }
    return bitmap
}

internal fun ReminderKind.notification(
    context: Context, channel: String, ar: Boolean, copy: ReminderCopy,
    whenMillis: Long, title: String = title(ar),
): Notification.Builder {
    val base = Notification.Builder(context, channel)
        .setSmallIcon(icon)
        .setLargeIcon(badge(context))
        .setColor(accent)
        .setWhen(whenMillis)
        .setShowWhen(true)
        .setAutoCancel(true)
    if (this != ReminderKind.UPDATE) {
        val publicKind = if (this == ReminderKind.GLUCOSE || this == ReminderKind.PRESSURE)
            ReminderKind.MEASUREMENT else this
        val redacted = Notification.Builder(context, channel)
            .setSmallIcon(publicKind.icon).setColor(publicKind.accent).setContentTitle(publicKind.title(ar))
            .setContentText(if (ar) "افتح يومي عشان تشوف التفاصيل" else "Open Yawmi to see the details")
            .setWhen(whenMillis).setShowWhen(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
        base.setVisibility(Notification.VISIBILITY_PRIVATE).setPublicVersion(redacted)
    }
    return base.setContentTitle(title).setContentText(copy.summary)
        .setStyle(Notification.BigTextStyle().bigText(copy.expanded))
}
