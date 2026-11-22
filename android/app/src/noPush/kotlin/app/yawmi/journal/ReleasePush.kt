package app.yawmi.journal

import android.app.Service
import android.content.Context
import android.content.Intent

internal object ReleasePush {
    const val configured = false
    fun sync(context: Context, enabled: Boolean) = Unit
}

class ReleasePushService : Service() {
    override fun onBind(intent: Intent?) = null
}
