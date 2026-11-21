package app.yawmi.journal

import java.time.LocalTime

internal fun widgetClockText(time: LocalTime, digits: String, format: String, system24: Boolean): String {
    val use24 = format == "24" || format == "system" && system24
    val hour = if (use24) time.hour else (time.hour % 12).let { if (it == 0) 12 else it }
    val hourText = if (use24) hour.toString().padStart(2, '0') else hour.toString()
    val value = "$hourText:${time.minute.toString().padStart(2, '0')}"
    if (digits != "ar") return value
    return value.map { if (it in '0'..'9') '٠' + (it - '0') else it }.joinToString("")
}
