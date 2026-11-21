package app.yawmi.journal

import android.Manifest
import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private val widgetWorker = Executors.newSingleThreadExecutor()
    }
    private lateinit var bridge: MethodChannel
    private var route: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        route = routeFrom(intent)
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.yawmi/android")
        bridge.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "takeRoute" -> { result.success(route); route = null }
                    "healthStatus" -> result.success(mapOf(
                        "available" to (Build.VERSION.SDK_INT >= 34 && YawmiHealthConnect.available(this)),
                        "granted" to healthGranted(this),
                    ))
                    "healthSettings" -> {
                        if (Build.VERSION.SDK_INT >= 34) YawmiHealthConnect.openPermissions(this)
                        result.success(null)
                    }
                    "healthRead" -> {
                        val types = call.arguments<List<String>>() ?: emptyList()
                        if (Build.VERSION.SDK_INT >= 34) YawmiHealthConnect.read(this, types, result)
                        else result.error("healthUnavailable", "Health Connect is unavailable", null)
                    }
                    "openUpdates" -> {
                        YawmiUpdates.onOpen(applicationContext, call.arguments == true)
                        result.success(YawmiUpdates.status(applicationContext))
                    }
                    "updateStatus" -> result.success(YawmiUpdates.status(applicationContext))
                    "checkUpdate" -> {
                        YawmiUpdates.check(applicationContext, manual = true)
                        result.success(null)
                    }
                    "automaticUpdates" -> {
                        YawmiUpdates.setAutomatic(applicationContext, call.argument<Boolean>("enabled") == true,
                            call.argument<Boolean>("arabic") == true)
                        result.success(null)
                    }
                    "downloadUpdate" -> {
                        YawmiUpdates.download(applicationContext)
                        result.success(null)
                    }
                    "installUpdate" -> result.success(YawmiUpdates.install(this))
                    "openFacebook" -> {
                        val page = Uri.parse(call.arguments as? String ?: "")
                        require(page.scheme == "https" &&
                            page.host in setOf("www.facebook.com", "facebook.com", "m.facebook.com", "fb.com") &&
                            !page.path.isNullOrBlank())
                        startActivity(Intent(Intent.ACTION_VIEW, page))
                        result.success(null)
                    }
                    "openPrivacy" -> {
                        val page = Uri.parse(call.arguments as String)
                        require(page.scheme == "https" && !page.host.isNullOrBlank())
                        startActivity(Intent(Intent.ACTION_VIEW, page))
                        result.success(null)
                    }
                    "reconcile" -> {
                        YawmiAlarms.reconcile(this, call.argument<String>("rules") ?: "[]",
                            call.argument<String>("resolved") ?: "[]", call.argument<String>("lang") ?: "en")
                        result.success(mapOf("allowed" to YawmiAlarms.allowed(this), "exact" to YawmiAlarms.exact(this)))
                    }
                    "permission" -> {
                        YawmiAlarms.prepareChannels(this)
                        if (Build.VERSION.SDK_INT >= 33 && !YawmiAlarms.allowed(this)) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 214)
                        }
                        result.success(null)
                    }
                    "notificationDiagnostics" -> result.success(YawmiAlarms.diagnostics(this))
                    "testNotification" -> result.success(YawmiAlarms.test(this,
                        call.argument<Boolean>("arabic") == true, call.argument<String>("channel")))
                    "settings" -> {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(null)
                    }
                    "battery" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "channel" -> {
                        YawmiAlarms.prepareChannels(this)
                        val channel = call.arguments as? String ?: error("Missing channel")
                        require(channel in setOf("medicine", "tracking", "habit"))
                        startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, channel))
                        result.success(null)
                    }
                    "exact" -> {
                        if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + packageName)))
                        result.success(null)
                    }
                    "pin" -> result.success(pin(call.argument<String>("id") ?: ""))
                    "publishWidgets" -> {
                        val raw = call.argument<String>("snapshot") ?: error("Missing widget data.")
                        val id = call.argument<Int>("widget")
                        val layout = call.argument<String>("layout")
                        widgetWorker.execute {
                            runCatching { YawmiWidget.publish(applicationContext, raw, id, layout) }
                                .onSuccess { runOnUiThread { result.success(null) } }
                                .onFailure { runOnUiThread { result.error("widget", "Could not update widget.", null) } }
                        }
                    }
                    "activeWidgetLayout" -> result.success(call.arguments?.let { (it as? Number)?.toInt() }
                        ?.let { YawmiWidget.activeLayout(this, it) })
                    "boundLayouts" -> result.success(YawmiWidget.usedLayouts(this).toList())
                    "installedWidgetIds" -> result.success(YawmiWidget.installedIds(this))
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("android", "The operation could not be completed.", null)
            }
        }
    }

    private fun routeFrom(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW_PERMISSION_USAGE &&
            intent.hasCategory("android.intent.category.HEALTH_PERMISSIONS")) {
            "privacy"
        } else if (intent?.action == "app.yawmi.OPEN" && intent.getStringExtra("token") == shortcutToken(this)) {
            intent.getStringExtra("route")
        } else null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val next = routeFrom(intent) ?: return
        if (::bridge.isInitialized) bridge.invokeMethod("open", next) else route = next
    }

    private fun pin(layout: String): Boolean {
        val manager = AppWidgetManager.getInstance(this)
        if (layout.isEmpty() || !manager.isRequestPinAppWidgetSupported) return false
        val callback = Intent(this, WidgetPinned::class.java)
            .setData(Uri.parse("yawmi://pin/" + layout)).putExtra("layout", layout)
        val pending = PendingIntent.getBroadcast(this, 0, callback, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
        return manager.requestPinAppWidget(YawmiWidget.component(this), null, pending)
    }
}

