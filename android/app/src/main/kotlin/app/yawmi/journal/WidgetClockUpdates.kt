package app.yawmi.journal

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors

class WidgetClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val task = goAsync()
        WidgetClockUpdates.tick(context.applicationContext, task::finish)
    }
}

internal object WidgetClockUpdates {
    private const val MINUTE = 60_000L
    private val worker = Executors.newSingleThreadExecutor()
    private var systemEvents: BroadcastReceiver? = null
    private var scheduledAt = 0L
    private var lastMinute = -1L

    @Synchronized
    fun sync(context: Context, hasClock: Boolean) {
        val app = context.applicationContext
        val alarm = app.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            app, 0, Intent(app, WidgetClockReceiver::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        if (!hasClock) {
            alarm.cancel(pending)
            systemEvents?.let(app::unregisterReceiver)
            systemEvents = null
            scheduledAt = 0L
            lastMinute = -1L
            return
        }

        if (systemEvents == null) {
            val events = WidgetClockReceiver()
            ContextCompat.registerReceiver(app, events, IntentFilter().apply {
                addAction(Intent.ACTION_TIME_TICK)
                addAction(Intent.ACTION_SCREEN_ON)
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            systemEvents = events
        }
        val at = (System.currentTimeMillis() / MINUTE + 1) * MINUTE
        if (scheduledAt == at) return
        // A display clock never needs to wake a sleeping device.
        if (YawmiAlarms.exact(app)) {
            try {
                alarm.setExact(AlarmManager.RTC, at, pending)
                scheduledAt = at
                return
            } catch (_: SecurityException) {
                // Exact access can change after the check.
            }
        }
        alarm.set(AlarmManager.RTC, at, pending)
        scheduledAt = at
    }

    fun tick(context: Context, finish: () -> Unit) {
        worker.execute {
            try {
                val minute = System.currentTimeMillis() / MINUTE
                val shouldDraw = synchronized(this) {
                    if (lastMinute == minute) false
                    else {
                        lastMinute = minute
                        true
                    }
                }
                val active = if (shouldDraw) YawmiWidget.refreshClocks(context)
                    else YawmiWidget.hasClocks(context)
                sync(context, active)
            } finally {
                finish()
            }
        }
    }
}
