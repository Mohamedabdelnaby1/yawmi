package app.yawmi.journal

import android.app.AlarmManager
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == YawmiAlarms.SNOOZE_ACTION) {
            val id = intent.getStringExtra("id") ?: return
            val key = intent.getStringExtra("occurrence") ?: return
            YawmiAlarms.snoozeFromNotice(context, id, key)
        } else if (intent.action == YawmiAlarms.STOP_ACTION) {
            val id = intent.getStringExtra("id") ?: return
            val key = intent.getStringExtra("occurrence") ?: return
            YawmiAlarms.stopFromNotice(context, id, key)
        } else if (intent.action == "app.yawmi.ALARM") {
            val id = intent.getStringExtra("id") ?: return
            YawmiAlarms.deliver(context, id, intent.getLongExtra("when", 0))
        } else {
            if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
                YawmiAlarms.interruptTest(context)
            }
            YawmiAlarms.schedule(context)
            YawmiWidget.refresh(context)
        }
    }
}

internal object YawmiAlarms {
    const val SNOOZE_ACTION = "app.yawmi.SNOOZE"
    const val STOP_ACTION = "app.yawmi.STOP_REPEAT"
    private const val MIDNIGHT = "_midnight"
    private const val TEST = "_diagnostic"
    private const val DISPATCH = "_next_reminder"
    private const val MINUTE = 60_000L
    private const val KEEP_MS = 8L * 24 * 60 * MINUTE
    private fun prefs(context: Context) = context.getSharedPreferences("yawmi_alarms", Context.MODE_PRIVATE)
    private fun alarm(context: Context) = context.getSystemService(AlarmManager::class.java)
    private fun notifier(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun allowed(context: Context) = notifier(context).areNotificationsEnabled()
    fun exact(context: Context) = Build.VERSION.SDK_INT < 31 || alarm(context).canScheduleExactAlarms()
    private fun jsonObject(context: Context, key: String) =
        runCatching { JSONObject(prefs(context).getString(key, "{}") ?: "{}") }.getOrDefault(JSONObject())
    private fun storedRules(context: Context): List<JSONObject> {
        val array = JSONArray(prefs(context).getString("rules", "[]"))
        return List(array.length()) { array.getJSONObject(it) }
    }
    private fun activeMedicineRule(rules: List<JSONObject>, key: String): JSONObject? {
        val fields = key.split(":")
        if (fields.size != 4) return null
        val id = listOf(fields[0], fields[1], fields[3]).joinToString(":")
        return rules.firstOrNull { it.optString("id") == id && it.optString("type") == "medicine" && !it.has("when") }
    }
    private fun savedSnoozes(context: Context): JSONObject =
        JSONObject(prefs(context).getString("notificationSnoozes", "{}") ?: "{}")

    private fun rules(context: Context): List<JSONObject> {
        val source = storedRules(context)
        val merged = source.associateBy { it.getString("id") }.toMutableMap()
        val done = resolved(context)
        val saved = savedSnoozes(context)
        val recent = JSONObject()
        val now = System.currentTimeMillis()
        for (key in saved.keys()) {
            val due = saved.optLong(key)
            if (due <= now - 86_400_000L || key in done) continue
            val original = activeMedicineRule(source, key) ?: continue
            recent.put(key, due)
            val id = "snooze:$key"
            val other = merged[id]?.optString("when")?.let { Instant.parse(it).toEpochMilli() } ?: 0L
            if (due <= other) continue
            merged[id] = JSONObject()
                .put("id", id).put("when", Instant.ofEpochMilli(due).toString())
                .put("type", "medicine").put("route", "dose/$key")
                .put("owner", original.optString("owner"))
                .put("quiet", original.optJSONObject("quiet"))
                .put("repeatCount", original.optInt("repeatCount"))
                .put("repeatMinutes", original.optInt("repeatMinutes", 15))
        }
        if (recent.length() != saved.length()) {
            prefs(context).edit().putString("notificationSnoozes", recent.toString()).apply()
        }
        return merged.values.toList()
    }

    private fun noticeAction(context: Context, action: String, id: String, key: String): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).setAction(action)
            .setData(Uri.Builder().scheme("yawmi").authority("action").appendPath(action).appendPath(id).appendPath(key).build())
            .putExtra("id", id).putExtra("occurrence", key)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun snoozeFromNotice(context: Context, id: String, key: String) {
        val tag = "$id/$key"
        val manager = notifier(context)
        if (manager.activeNotifications.none { it.tag == tag && it.id == 1 } ||
            key in resolved(context) || activeMedicineRule(storedRules(context), key) == null) return
        val saved = savedSnoozes(context).put(key, System.currentTimeMillis() + 600_000L)
        prefs(context).edit().putString("notificationSnoozes", saved.toString()).apply()
        if (id != "snooze:$key") muteOccurrence(context, id, key)
        manager.cancel(tag, 1)
        schedule(context)
    }
    private fun occurrenceTag(id: String, key: String) = "$id/$key"

    private fun muteOccurrence(context: Context, id: String, key: String) {
        val stopped = jsonObject(context, "stoppedRepeats").put(occurrenceTag(id, key), System.currentTimeMillis())
        prefs(context).edit().putString("stoppedRepeats", stopped.toString()).apply()
    }

    fun stopFromNotice(context: Context, id: String, key: String) {
        val tag = occurrenceTag(id, key)
        val manager = notifier(context)
        if (manager.activeNotifications.none { it.tag == tag && it.id == 1 }) return
        muteOccurrence(context, id, key)
        manager.cancel(tag, 1)
        schedule(context)
    }
    private fun resolved(context: Context): Set<String> {
        val list = JSONArray(prefs(context).getString("resolved", "[]"))
        return List(list.length()) { list.getString(it) }.toSet()
    }

    fun reconcile(context: Context, rules: String, resolved: String, language: String) {
        prefs(context).edit().putString("rules", rules).putString("resolved", resolved).putString("lang", language).apply()
        schedule(context)
    }

    private data class Occurrence(val millis: Long, val key: String, val silent: Boolean = false)
    private data class ReminderAlarm(
        val rule: JSONObject, val occurrence: Occurrence, val original: Long,
        val identity: String, val priorCount: Int,
    )

    private fun sentKey(rule: JSONObject, key: String): String {
        val id = rule.getString("id")
        return "$id/" + if (rule.has("when") && !rule.optBoolean("stableOnce"))
            Instant.parse(rule.getString("when")).toEpochMilli().toString() else key
    }

    private fun nextAlarm(
        rule: JSONObject, now: Long, zone: ZoneId, done: Set<String>, delivered: JSONObject,
        stopped: JSONObject, legacySent: Set<String>, activeChannels: Set<String>,
    ): ReminderAlarm? {
        val id = rule.getString("id")
        val type = rule.optString("type", "tracking")
        if (type !in activeChannels) return null
        val repeats = rule.optInt("repeatCount").coerceIn(0, 3)
        val spacing = rule.optInt("repeatMinutes", 15).coerceIn(10, 60) * MINUTE
        val defaultGrace = if (type == "medicine") 120 else if (type == "habit") 60 else 90
        val grace = rule.optInt("graceMinutes", defaultGrace).coerceIn(30, 1440) * MINUTE
        val hardLimit = rule.optInt("maxDelay").takeIf { it > 0 }?.times(MINUTE)

        fun candidate(at: Instant, key: String): ReminderAlarm? {
            if (key in done || stopped.has(occurrenceTag(id, key))) return null
            val tag = sentKey(rule, key)
            val previous = delivered.optJSONObject(tag)
            val legacy = tag in legacySent || (!rule.has("when") && type != "medicine" && legacySent.any {
                it.startsWith("$id:") && it.substringAfter('/').endsWith(":" + key.substringAfterLast(':'))
            })
            val count = previous?.optInt("count") ?: if (legacy) 1 else 0
            if (count > repeats) return null
            val adjusted = quietOccurrence(rule, at.atZone(zone).toLocalDateTime(), zone, key, at) ?: return null
            val deadline = minOf(
                adjusted.millis + maxOf(grace, repeats * spacing + 20 * MINUTE),
                hardLimit?.let { at.toEpochMilli() + it } ?: Long.MAX_VALUE,
            )
            if (now >= deadline) return null
            val due = if (count == 0) adjusted else {
                val next = Instant.ofEpochMilli((previous?.optLong("at") ?: adjusted.millis) + spacing)
                quietOccurrence(rule, next.atZone(zone).toLocalDateTime(), zone, key, next) ?: return null
            }
            if (due.millis >= deadline || (due.silent && "quiet" !in activeChannels)) return null
            return ReminderAlarm(rule, due, at.toEpochMilli(), tag, count)
        }

        if (rule.has("when")) {
            return candidate(Instant.parse(rule.getString("when")), id.removePrefix("snooze:"))
        }
        val earliest = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().minusDays(1)
        val start = if (rule.isNull("start")) earliest else LocalDate.parse(rule.getString("start"))
        val end = if (rule.isNull("end")) null else LocalDate.parse(rule.getString("end"))
        val effective = if (rule.isNull("effective")) null else Instant.parse(rule.getString("effective"))
        val first = maxOf(earliest, start, effective?.atZone(zone)?.toLocalDate() ?: earliest)
        val minute = rule.getInt("minute")
        val shift = rule.optInt("shiftMinutes").coerceIn(-180, 180)
        val shiftStart = if (shift == 0) null else runCatching { LocalDate.parse(rule.optString("shiftStart")) }.getOrNull()
        val shiftEnd = if (shift == 0) null else runCatching { LocalDate.parse(rule.optString("shiftEnd")) }.getOrNull()
        val days = rule.getJSONArray("days")
        val allowedDays = List(days.length()) { days.getInt(it) }
        val medicine = rule.optString("medicine")
        val intervalDays = rule.optInt("intervalDays", 0).coerceIn(0, 14)
        var soonest: ReminderAlarm? = null
        for (offset in 0L..maxOf(14L, intervalDays.toLong() + 7)) {
            val day = first.plusDays(offset)
            if (end != null && day.isAfter(end)) break
            if (day.dayOfWeek.value !in allowedDays) continue
            if (intervalDays > 0) {
                val daysSinceFirst = ChronoUnit.DAYS.between(start, day)
                if (daysSinceFirst <= 0 || daysSinceFirst % intervalDays != 0L) continue
            }
            val adjusted = if (shiftStart != null && shiftEnd != null && day >= shiftStart &&
                day <= shiftEnd && (minute + shift) in 0..1439) minute + shift else minute
            val instant = resolveLocal(day.atTime(adjusted / 60, adjusted % 60), zone)
            if (effective != null && instant.isBefore(effective)) continue
            if (soonest != null && instant.toEpochMilli() > soonest.occurrence.millis) break
            val key = if (medicine.isEmpty()) "$id:$day" else
                listOf(medicine, rule.getInt("revision"), day, minute).joinToString(":")
            val alarm = candidate(instant, key) ?: continue
            if (soonest == null || alarm.occurrence.millis < soonest.occurrence.millis) soonest = alarm
        }
        return soonest
    }

    private fun quietOccurrence(rule: JSONObject, local: LocalDateTime, zone: ZoneId, key: String, at: Instant): Occurrence? {
        val quiet = rule.optJSONObject("quiet") ?: return Occurrence(at.toEpochMilli(), key)
        val start = quiet.optInt("start", -1)
        val end = quiet.optInt("end", -1)
        val minute = local.hour * 60 + local.minute
        if (start !in 0..1439 || end !in 0..1439 || start == end) return Occurrence(at.toEpochMilli(), key)
        val inside = if (start < end) minute >= start && minute < end else minute >= start || minute < end
        if (!inside) return Occurrence(at.toEpochMilli(), key)
        return when (quiet.optString("mode")) {
            "skip" -> null
            "silent" -> Occurrence(at.toEpochMilli(), key, true)
            "defer" -> {
                val shift = if (start > end && minute >= start) 1L else 0L
                val adjusted = local.toLocalDate().plusDays(shift).atTime(end / 60, end % 60)
                Occurrence(resolveLocal(adjusted, zone).toEpochMilli(), key)
            }
            else -> Occurrence(at.toEpochMilli(), key)
        }
    }

    private fun resolveLocal(local: LocalDateTime, zone: ZoneId): Instant {
        val offsets = zone.rules.getValidOffsets(local)
        return if (offsets.isEmpty()) zone.rules.getTransition(local).instant else local.toInstant(offsets.first())
    }

    private fun pending(context: Context, id: String, occurrence: Occurrence? = null, flags: Int = PendingIntent.FLAG_UPDATE_CURRENT): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java).setAction("app.yawmi.ALARM")
            .setData(Uri.Builder().scheme("yawmi").authority("alarm").appendPath(id).build())
            .putExtra("id", id)
        if (occurrence != null) intent.putExtra("occurrence", occurrence.key).putExtra("when", occurrence.millis)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or flags)
    }

    private fun set(context: Context, id: String, occur: Occurrence, precise: Boolean): Boolean {
        val intent = pending(context, id, occur) ?: return false
        val manager = alarm(context)
        if (precise) {
            try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, occur.millis, intent)
                return true
            } catch (_: SecurityException) {
                // The system can revoke special access between checking and scheduling.
            }
        }
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, occur.millis, intent)
        return false
    }

    fun diagnostics(context: Context): Map<String, Any> {
        val stored = prefs(context)
        return mapOf("allowed" to allowed(context), "exact" to exact(context),
            "state" to (stored.getString("testState", "idle") ?: "idle"),
            "at" to stored.getLong("testAt", 0L),
            "lastReminder" to stored.getLong("lastReminderPost", 0L),
            "scheduled" to stored.getInt("queueCount", 0),
            "next" to stored.getLong("nextReminderAt", 0L),
            "delay" to stored.getLong("lastReminderDelay", 0L),
            "audit" to readAudit(context),
            "restricted" to (Build.VERSION.SDK_INT >= 28 &&
                context.getSystemService(ActivityManager::class.java).isBackgroundRestricted),
            "channels" to channelStatus(context))
    }

    private fun readAudit(context: Context): List<Map<String, Any>> {
        val log = runCatching { JSONArray(prefs(context).getString("audit", "[]")) }.getOrDefault(JSONArray())
        return (0 until log.length()).mapNotNull { index ->
            log.optJSONObject(index)?.let { row -> mapOf(
                "kind" to row.optString("kind"), "state" to row.optString("state"),
                "due" to row.optLong("due"), "actual" to row.optLong("actual")
            ) }
        }
    }

    private fun recordAudit(context: Context, kind: String, state: String, due: Long, actual: Long = 0L) {
        val now = System.currentTimeMillis()
        val log = JSONArray().put(JSONObject(mapOf("kind" to kind, "state" to state, "due" to due, "actual" to actual)))
        readAudit(context)
            .filter { (it["due"] as Long) >= now - KEEP_MS }
            .take(29).forEach { log.put(JSONObject(it)) }
        prefs(context).edit().putString("audit", log.toString()).apply()
    }

    fun interruptTest(context: Context) {
        val stored = prefs(context)
        if (stored.getString("testState", "")?.startsWith("queued") == true) {
            pending(context, TEST, flags = PendingIntent.FLAG_NO_CREATE)?.cancel()
            stored.edit().putString("testState", "interrupted").putLong("testAt", System.currentTimeMillis()).apply()
        }
    }

    fun test(context: Context, arabic: Boolean, requested: String?, locked: Boolean): Map<String, Any> {
        val stored = prefs(context)
        val manager = notifier(context)
        val channel = requested?.takeIf { it in setOf("medicine", "tracking", "habit") } ?: "tracking"
        channelStatus(context)
        val due = System.currentTimeMillis() + if (locked) MINUTE else 10_000L
        val state = when {
            !allowed(context) -> "blocked"
            manager.getNotificationChannel(channel)?.importance == NotificationManager.IMPORTANCE_NONE -> "channelBlocked"
            else -> if (set(context, TEST, Occurrence(due, due.toString()), exact(context))) "queuedExact" else "queuedApproximate"
        }
        stored.edit().putString("testState", state).putBoolean("testArabic", arabic)
            .putString("testChannel", channel)
            .putLong("testAt", if (state.startsWith("queued")) due else System.currentTimeMillis()).apply()
        recordAudit(context, "test", state, due)
        return diagnostics(context)
    }

    private fun createTrackingChannel(manager: NotificationManager, ar: Boolean) {
        manager.createNotificationChannel(NotificationChannel("tracking",
            if (ar) "القياسات والتذكيرات" else "Tracking and reminders", NotificationManager.IMPORTANCE_DEFAULT))
    }

    fun prepareChannels(context: Context) {
        channelStatus(context)
    }

    private fun deliverTest(context: Context, due: Long) {
        val store = prefs(context)
        val state = store.getString("testState", "") ?: ""
        if (!state.startsWith("queued") || store.getLong("testAt", 0) != due) return
        val ar = store.getBoolean("testArabic", false)
        val channel = store.getString("testChannel", "tracking") ?: "tracking"
        val manager = notifier(context)
        channelStatus(context)
        val result = when {
            !allowed(context) -> "blocked"
            manager.getNotificationChannel(channel)?.importance == NotificationManager.IMPORTANCE_NONE -> "channelBlocked"
            else -> try {
                val notice = Notification.Builder(context, channel).setSmallIcon(R.drawable.ic_reminder)
                    .setContentTitle(if (ar) "تنبيه تجريبي من يومي" else "Yawmi test notification")
                    .setContentText(if (ar) "ده اختبار للإشعارات على الجهاز." else "This checks notifications on this device.")
                    .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true)
                    .setContentIntent(appShortcut(context, "routine", "diagnostic")).build()
                manager.notify("yawmi-test", 1, notice)
                "posted"
            } catch (_: SecurityException) { "blocked" }
        }
        store.edit().putString("testState", result).putLong("testAt", System.currentTimeMillis()).apply()
        recordAudit(context, "test", result, due, if (result == "posted") System.currentTimeMillis() else 0L)
    }

    private fun channelStatus(context: Context): Map<String, Boolean> {
        val ar = prefs(context).getString("lang", "en") == "ar"
        val manager = notifier(context)
        createTrackingChannel(manager, ar)
        manager.createNotificationChannel(NotificationChannel("medicine", if (ar) "الأدوية" else "Medication", NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel("habit", if (ar) "المياه والعادات" else "Water and habits", NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel("quiet", if (ar) "ساعات الهدوء" else "Quiet hours", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null)
            enableVibration(false)
        })
        return listOf("medicine", "tracking", "habit", "quiet").associateWith {
            manager.getNotificationChannel(it)?.importance != NotificationManager.IMPORTANCE_NONE
        }
    }

    private fun trimLog(log: JSONObject, now: Long, time: (String) -> Long) {
        val keys = log.keys().asSequence().toList()
        for (key in keys) if (time(key) < now - KEEP_MS) log.remove(key)
        for (key in log.keys().asSequence().toList().sortedByDescending(time).drop(1024)) log.remove(key)
    }

    private fun nextAlarms(
        context: Context, rules: List<JSONObject>, now: Long, delivered: JSONObject,
        stopped: JSONObject, done: Set<String>,
    ): List<ReminderAlarm> {
        if (!allowed(context)) return emptyList()
        val channels = channelStatus(context).filterValues { it }.keys
        val legacy = prefs(context).getStringSet("sent", emptySet()).orEmpty()
        val zone = ZoneId.systemDefault()
        val snoozed = rules.mapNotNull { row ->
            val id = row.optString("id")
            id.removePrefix("snooze:").takeIf { it != id }
        }.toSet()
        return rules.mapNotNull { rule ->
            val suppress = if (rule.optString("type") == "medicine" && !rule.has("when")) done + snoozed else done
            runCatching { nextAlarm(rule, now, zone, suppress, delivered, stopped, legacy, channels) }.getOrNull()
        }.sortedBy { it.occurrence.millis }
    }

    fun schedule(context: Context) {
        val store = prefs(context)
        val rules = rules(context)
        val done = resolved(context)
        val manager = notifier(context)
        val activeIds = rules.map { it.getString("id") }.toSet()
        for (notice in manager.activeNotifications) {
            val parts = notice.tag?.split("/", limit = 2) ?: continue
            if (parts.size == 2 && (parts[0] !in activeIds || parts[1] in done)) manager.cancel(notice.tag, notice.id)
        }

        val now = System.currentTimeMillis()
        val delivered = jsonObject(context, "deliveries")
        val stopped = jsonObject(context, "stoppedRepeats")
        trimLog(delivered, now) { delivered.optJSONObject(it)?.optLong("at") ?: 0L }
        trimLog(stopped, now, stopped::optLong)
        val queue = nextAlarms(context, rules, now, delivered, stopped, done)
        val upcoming = queue.firstOrNull()
        val scheduled = mutableSetOf(MIDNIGHT)
        if (upcoming != null) {
            set(context, DISPATCH, Occurrence(maxOf(now + 350, upcoming.occurrence.millis), DISPATCH), exact(context))
            scheduled.add(DISPATCH)
        }
        val zone = ZoneId.systemDefault()
        val tomorrow = LocalDate.now(zone).plusDays(1)
        set(context, MIDNIGHT, Occurrence(tomorrow.atStartOfDay(zone).toInstant().toEpochMilli(), tomorrow.toString()), false)
        for (id in store.getStringSet("scheduled", emptySet()).orEmpty() - scheduled) {
            pending(context, id, flags = PendingIntent.FLAG_NO_CREATE)?.let { alarm(context).cancel(it); it.cancel() }
        }
        store.edit().putStringSet("scheduled", scheduled)
            .putLong("nextReminderAt", upcoming?.occurrence?.millis ?: 0L)
            .putInt("queueCount", queue.size)
            .putString("deliveries", delivered.toString())
            .putString("stoppedRepeats", stopped.toString())
            .apply()
    }

    fun deliver(context: Context, id: String, due: Long) {
        if (id == TEST) return deliverTest(context, due)
        if (id == MIDNIGHT) {
            YawmiWidget.refresh(context)
            return schedule(context)
        }
        val store = prefs(context)
        val rules = rules(context)
        val done = resolved(context)
        val posted = jsonObject(context, "deliveries")
        val stopped = jsonObject(context, "stoppedRepeats")
        val manager = notifier(context)
        val now = System.currentTimeMillis()
        val ar = store.getString("lang", "en") == "ar"
        if (!allowed(context)) {
            recordAudit(context, "tracking", "blocked", due)
            return schedule(context)
        }
        val recent = nextAlarms(context, rules, now, posted, stopped, done)
        var last: ReminderAlarm? = null
        for (next in recent.takeWhile { it.occurrence.millis <= now + 400 }.take(20)) {
            val rule = next.rule
            val ruleId = rule.getString("id")
            val key = next.occurrence.key
            val channel = rule.optString("type", "tracking")
            val title = rule.optString("title", if (ar) "تذكير من يومي" else "Yawmi reminder")
            val description = if (now - next.original >= 10 * MINUTE) {
                if (ar) "الميعاد عدى. افتح يومي وراجع التسجيل." else "The scheduled time passed. Open Yawmi to review."
            } else if (next.priorCount > 0) {
                if (ar) "لسه مفيش تسجيل للميعاد ده. افتح يومي تراجعه." else "No entry for this reminder yet. Open Yawmi to review."
            } else {
                if (ar) "افتح يومي وشوف تفاصيل الميعاد." else "Open Yawmi to see the reminder."
            }
            val route = if (!rule.isNull("tracker") && rule.optString("tracker").isNotBlank())
                "reminder/${rule.optString("origin", ruleId)}/" + key.substringAfterLast(':')
                else rule.optString("route").ifEmpty { if (channel == "medicine") "dose/$key" else "routine" }
            val owner = rule.optString("owner")
            val scopedRoute = if (owner.isBlank()) route else "profile/$owner/$route"
            val tag = occurrenceTag(ruleId, key)
            val notice = Notification.Builder(context, if (next.occurrence.silent) "quiet" else channel)
                .setSmallIcon(R.drawable.ic_reminder)
                .setContentTitle(title).setContentText(description).setVisibility(Notification.VISIBILITY_PRIVATE)
                .setShowWhen(true).setWhen(next.original)
                .setContentIntent(appShortcut(context, scopedRoute, "notification-$tag")).setAutoCancel(true)
            if (channel == "medicine" && activeMedicineRule(rules, key) != null) {
                notice.addAction(Notification.Action.Builder(
                    null, if (ar) "أجّل ١٠ دقايق" else "Snooze 10 min", noticeAction(context, SNOOZE_ACTION, ruleId, key)
                ).build())
            }
            if (rule.optInt("repeatCount") > next.priorCount) {
                notice.addAction(Notification.Action.Builder(
                    null, if (ar) "أوقف التكرار" else "Stop repeats", noticeAction(context, STOP_ACTION, ruleId, key)
                ).build())
            }
            try {
                manager.notify(tag, 1, notice.build())
            } catch (_: SecurityException) {
                recordAudit(context, channel, "blocked", next.occurrence.millis)
                break
            }
            recordAudit(context, channel, "posted", next.occurrence.millis, now)
            posted.put(next.identity, JSONObject().put("at", now).put("count", next.priorCount + 1))
            last = next
        }
        if (last != null) {
            store.edit().putString("deliveries", posted.toString()).putLong("lastReminderPost", now)
                .putLong("lastReminderDelay", maxOf(0, now - last.occurrence.millis)).apply()
        }
        schedule(context)
    }
}
