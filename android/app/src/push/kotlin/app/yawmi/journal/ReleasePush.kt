package app.yawmi.journal

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

internal object ReleasePush {
    const val configured = true
    const val TOPIC = "yawmi-release-v1"
    private var pending: Boolean? = null

    @Synchronized
    fun sync(context: Context, enabled: Boolean) {
        val store = context.getSharedPreferences("yawmi_release_push", Context.MODE_PRIVATE)
        if (pending == enabled || pending == null && store.contains("subscribed") &&
            store.getBoolean("subscribed", false) == enabled) return
        pending = enabled
        try {
            if (FirebaseApp.getApps(context).isEmpty()) {
                FirebaseApp.initializeApp(context)
            }
            val messaging = FirebaseMessaging.getInstance()
            val task = if (enabled) messaging.subscribeToTopic(TOPIC) else messaging.unsubscribeFromTopic(TOPIC)
            task.addOnCompleteListener {
                synchronized(this) {
                    if (pending == enabled) {
                        pending = null
                        if (it.isSuccessful) store.edit().putBoolean("subscribed", enabled).apply()
                    }
                }
            }
        } catch (_: RuntimeException) {
            pending = null
        }
    }
}

class ReleasePushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.from != "/topics/${ReleasePush.TOPIC}") return
        val version = message.data["version"] ?: return
        if (!Regex("[0-9]{1,5}\\.[0-9]{1,5}\\.[0-9]{1,5}").matches(version)) return
        YawmiUpdates.releaseHint(applicationContext, version)
    }
}
