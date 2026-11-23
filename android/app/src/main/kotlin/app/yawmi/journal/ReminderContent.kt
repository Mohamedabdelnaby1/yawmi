package app.yawmi.journal

import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

internal enum class ReminderKind(
    val key: String,
    val arabicTitle: String,
    val englishTitle: String,
    val arabicAction: String,
    val englishAction: String,
) {
    MEDICINE("medicine", "ميعاد الدوا", "Medication due", "سجّل الجرعة", "Log dose"),
    GLUCOSE("glucose", "ميعاد قياس السكر", "Blood glucose check", "سجّل القياس", "Log reading"),
    PRESSURE("pressure", "ميعاد قياس الضغط", "Blood pressure check", "سجّل القياس", "Log reading"),
    MEASUREMENT("measurement", "ميعاد قياس", "Measurement due", "سجّل القياس", "Log reading"),
    WATER("water", "وقت الميّه", "Water reminder", "افتح تسجيل الميّه", "Open water log"),
    SLEEP("sleep", "ميعاد متابعة النوم", "Sleep reminder", "افتح تسجيل النوم", "Open sleep log"),
    STOCK("stock", "مخزون الدوا قليل", "Medication stock is low", "افتح المخزون", "View stock"),
    FORECAST("forecast", "موعد نفاد المخزون", "Estimated stock runout", "افتح المخزون", "View stock"),
    EXPIRY("expiry", "صلاحية الدوا", "Medication expiry", "راجع الصلاحية", "Review expiry"),
    LAB("lab", "ميعاد تحليل", "Lab follow-up", "افتح المتابعة", "View follow-up"),
    VISIT("visit", "ميعاد زيارة", "Visit reminder", "افتح الزيارة", "View visit"),
    FOLLOW_UP("followUp", "ميعاد متابعة", "Follow-up reminder", "افتح المتابعة", "View follow-up"),
    TRACKING("tracking", "تذكير بمتابعة", "Tracking reminder", "افتح التسجيل", "Open log"),
    UPDATE("update", "تحديث جديد ليومي", "A new Yawmi update", "حدّث دلوقتي", "Update now");

    fun title(ar: Boolean) = if (ar) arabicTitle else englishTitle
    fun action(ar: Boolean) = if (ar) arabicAction else englishAction
    val channel: String get() = when (this) {
        MEDICINE -> "medicine"
        WATER, SLEEP -> "habit"
        else -> "tracking"
    }

    companion object {
        fun fromKey(key: String) = entries.firstOrNull { it.key == key }

        fun fromRule(rule: JSONObject): ReminderKind {
            fromKey(rule.optJSONObject("notice")?.optString("kind").orEmpty())?.let { return it }
            if (rule.optString("type") == "medicine") return MEDICINE
            when (rule.optString("tracker")) {
                "glucose" -> return GLUCOSE
                "pressure" -> return PRESSURE
                "water" -> return WATER
                "sleep" -> return SLEEP
                "lab" -> return LAB
                "visit" -> return VISIT
            }
            return when (rule.optString("route").substringBefore('/')) {
                "expiry", "packs" -> EXPIRY
                "stock" -> if (rule.optString("origin", rule.optString("id")).startsWith("forecast:")) FORECAST else STOCK
                "follow-up" -> FOLLOW_UP
                else -> if (rule.optString("route").startsWith("add/")) MEASUREMENT else TRACKING
            }
        }
    }
}

internal data class ReminderCopy(val summary: String, val expanded: String)

private val controlChars = Regex("[\\p{Cc}\\u202A-\\u202E\\u2066-\\u2069]+")
private val whitespace = Regex("\\s+")
private fun String.noticeLine() = replace(controlChars, " ").replace(whitespace, " ").trim().take(120)

internal fun reminderCopy(
    kind: ReminderKind, rule: JSONObject, ar: Boolean, scheduledTime: String,
    repeated: Boolean = false, late: Boolean = false, snoozed: Boolean = false,
): ReminderCopy {
    val notice = rule.optJSONObject("notice")
    val subject = notice?.optString("subject").orEmpty().noticeLine()
    val details = notice?.optJSONArray("details")?.let { array ->
        (0 until array.length()).mapNotNull { (array.opt(it) as? String)?.noticeLine() }.filter { it.isNotEmpty() }.take(3)
    }.orEmpty()
    val date = notice?.optString("date")?.takeIf { it.isNotBlank() }?.let { value ->
        runCatching { LocalDate.parse(value).format(DateTimeFormatter.ofPattern("d MMM yyyy", if (ar) Locale.forLanguageTag("ar-EG") else Locale.ENGLISH)) }
            .getOrNull()
    }
    val dateLine = date?.let {
        val label = when (kind) {
            ReminderKind.EXPIRY -> if (ar) "الصلاحية لحد" else "Expires"
            ReminderKind.FORECAST -> if (ar) "النفاد المتوقع" else "Estimated runout"
            else -> if (ar) "تاريخ الميعاد" else "Due on"
        }
        "$label $it"
    }
    val timeLine = when {
        snoozed -> if (ar) "بعد التأجيل · $scheduledTime" else "Snoozed until $scheduledTime"
        repeated -> if (ar) "تذكير تاني · الميعاد كان $scheduledTime" else "Repeat reminder · scheduled for $scheduledTime"
        late -> if (ar) "الميعاد كان $scheduledTime" else "Scheduled for $scheduledTime"
        else -> if (ar) "الميعاد $scheduledTime" else "Scheduled for $scheduledTime"
    }
    val primary = listOfNotNull(subject.takeIf { it.isNotBlank() }, dateLine ?: details.firstOrNull())
    val summary = if (primary.isEmpty()) timeLine else primary.joinToString(" · ")
    return ReminderCopy(
        summary,
        listOfNotNull(subject.takeIf { it.isNotBlank() }, *details.toTypedArray(), dateLine, timeLine)
            .distinct().joinToString("\n"),
    )
}
