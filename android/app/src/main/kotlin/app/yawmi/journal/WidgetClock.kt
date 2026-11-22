package app.yawmi.journal

import java.time.LocalTime

internal fun widgetClockText(
    time: LocalTime, digits: String, format: String, system24: Boolean, showPeriod: Boolean = false,
): String {
    val use24 = format == "24" || format == "system" && system24
    val hour = if (use24) time.hour else (time.hour % 12).let { if (it == 0) 12 else it }
    val hourText = if (use24) hour.toString().padStart(2, '0') else hour.toString()
    val period = if (!use24 && showPeriod) {
        if (digits == "ar") (if (time.hour < 12) " ص" else " م")
        else (if (time.hour < 12) " AM" else " PM")
    } else ""
    val value = "$hourText:${time.minute.toString().padStart(2, '0')}$period"
    if (digits != "ar") return value
    return value.map { if (it in '0'..'9') '٠' + (it - '0') else it }.joinToString("")
}

internal fun widgetDoseTimeText(value: String, digits: String, format: String, system24: Boolean): String {
    if (value.length != 5 || value[2] != ':' || value[0] !in '0'..'2') return value
    val time = runCatching { LocalTime.parse(value) }.getOrNull() ?: return value
    return widgetClockText(time, digits, format, system24, showPeriod = true)
}
