package app.yawmi.journal

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.URI
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

class UpdateFileProvider : FileProvider()

class UpdateJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        if (!YawmiUpdates.active(applicationContext)) return false
        YawmiUpdates.check(applicationContext) { jobFinished(params, false) }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = false
}

private const val JOB_ID = 81914
private const val UPDATE_NOTICE = 81915
private const val PUSH_JOB_ID = 81916

internal object YawmiUpdates {
    private val worker = Executors.newSingleThreadExecutor()
    private val downloads = Executors.newSingleThreadExecutor()
    private val hosts = setOf(
        "api.github.com", "github.com", "release-assets.githubusercontent.com",
        "objects.githubusercontent.com", "github-releases.githubusercontent.com",
    )
    @Volatile private var checking = false
    @Volatile private var downloadProgress = -1
    @Volatile private var error = ""

    private fun prefs(c: Context) = c.getSharedPreferences("yawmi_updates", Context.MODE_PRIVATE)
    fun active(c: Context) = BuildConfig.GITHUB_UPDATES && prefs(c).getBoolean("automatic", true)

    private fun installed(c: Context) = c.packageManager.getPackageInfo(
        c.packageName, signingFlag()
    )

    private fun release(c: Context): YawmiRelease? = prefs(c).getString("release", null)?.let { raw ->
        runCatching { YawmiRelease.read(JSONObject(raw)) }.getOrNull()
            ?.takeIf { newer(it.version, installed(c).versionName.orEmpty()) }
    }

    fun setAutomatic(c: Context, enabled: Boolean, ar: Boolean) {
        if (!BuildConfig.GITHUB_UPDATES) return
        prefs(c).edit().putBoolean("automatic", enabled).apply()
        if (enabled) onOpen(c, ar) else {
            c.getSystemService(JobScheduler::class.java).cancel(JOB_ID)
            c.getSystemService(JobScheduler::class.java).cancel(PUSH_JOB_ID)
            c.getSystemService(NotificationManager::class.java).cancel(UPDATE_NOTICE)
        }
        ReleasePush.sync(c, enabled)
    }

    fun onOpen(c: Context, ar: Boolean) {
        if (!BuildConfig.GITHUB_UPDATES) return
        val store = prefs(c)
        if (store.getBoolean("arabic", false) != ar) store.edit().putBoolean("arabic", ar).apply()
        if (store.getString("release", null) != null && release(c) == null) {
            store.edit().remove("release").remove("verified").apply()
            File(c.cacheDir, "release-update").listFiles()?.forEach { it.delete() }
        }
        if (!active(c)) return
        ReleasePush.sync(c, true)
        val jobs = c.getSystemService(JobScheduler::class.java)
        val interval = TimeUnit.MINUTES.toMillis(15)
        val pending = jobs.getPendingJob(JOB_ID)
        if (pending == null || pending.intervalMillis != interval) {
            jobs.schedule(JobInfo.Builder(JOB_ID, ComponentName(c, UpdateJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(interval)
                .setPersisted(true)
                .build())
        }
        val since = System.currentTimeMillis() - prefs(c).getLong("lastAttempt", 0)
        val retryAfter = if (error == "check") 5 else 1
        if (since !in 0 until TimeUnit.MINUTES.toMillis(retryAfter.toLong())) check(c)
    }

    fun releaseHint(c: Context, version: String) {
        if (!active(c) || !newer(version, installed(c).versionName.orEmpty())) return
        c.getSystemService(JobScheduler::class.java).schedule(
            JobInfo.Builder(PUSH_JOB_ID, ComponentName(c, UpdateJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setOverrideDeadline(10_000)
                .build()
        )
        check(c)
    }

    @Synchronized
    fun check(c: Context, manual: Boolean = false, finish: () -> Unit = {}) {
        if (!BuildConfig.GITHUB_UPDATES || checking) {
            finish()
            return
        }
        checking = true
        if (error == "check") error = ""
        val store = prefs(c)
        store.edit().putLong("lastAttempt", System.currentTimeMillis()).apply()
        worker.execute {
            try {
                val previous = release(c)
                val connection = connect(
                    "https://api.github.com/repos/$PROJECT/releases/latest",
                    releaseApi = true,
                    etag = store.getString("etag", null),
                )
                var responseTag: String? = null
                var changedResponse = false
                val latest = try {
                    when (connection.responseCode) {
                        304 -> previous
                        404 -> null
                        200 -> {
                            changedResponse = true
                            responseTag = connection.getHeaderField("ETag")
                            val bytes = connection.inputStream.use { input ->
                                val buffer = ByteArray(4096)
                                val output = ByteArrayOutputStream()
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    require(output.size() + count <= 131072)
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray()
                            }
                            val found = YawmiRelease.fromGitHub(
                                JSONObject(String(bytes, Charsets.UTF_8)),
                                installed(c).versionName.orEmpty(),
                            )
                            found
                        }
                        else -> throw IOException("GitHub release response")
                    }
                } finally {
                    connection.disconnect()
                }
                store.edit().putString("release", latest?.toJson()?.toString())
                    .apply { if (changedResponse) putString("etag", responseTag) }
                    .putLong("lastSuccess", System.currentTimeMillis()).apply()
                if (latest == null) c.getSystemService(NotificationManager::class.java).cancel(UPDATE_NOTICE)
                else if (!manual && active(c)) notifyUpdate(c, latest)
            } catch (_: Exception) {
                error = "check"
            } finally {
                checking = false
                finish()
            }
        }
    }

    fun status(c: Context): Map<String, Any?> {
        if (!BuildConfig.GITHUB_UPDATES) return mapOf("enabled" to false)
        val offer = release(c)
        return mapOf(
            "enabled" to true, "automatic" to active(c), "checking" to checking,
            "installed" to installed(c).versionName, "version" to offer?.version,
            "size" to offer?.size, "notes" to offer?.notes, "checkedAt" to prefs(c).getLong("lastSuccess", 0),
            "progress" to downloadProgress, "ready" to (offer != null && ready(c, offer)),
            "error" to error,
            "push" to ReleasePush.configured,
        )
    }

    @Synchronized
    fun download(c: Context) {
        if (!BuildConfig.GITHUB_UPDATES || downloadProgress >= 0) return
        val offer = release(c) ?: return
        if (ready(c, offer)) return
        error = ""
        downloadProgress = 0
        downloads.execute {
            val target = apkFile(c, offer)
            val partial = File(target.parentFile, "update.part.apk")
            try {
                target.parentFile!!.mkdirs()
                target.parentFile!!.listFiles()?.filter { it.name != partial.name }?.forEach { it.delete() }
                prefs(c).edit().remove("verified").apply()
                val digest = MessageDigest.getInstance("SHA-256")
                val connection = connect(offer.apkUrl)
                try {
                    require(connection.responseCode == 200)
                    connection.inputStream.use { from ->
                        partial.outputStream().buffered().use { to ->
                            val buffer = ByteArray(65536)
                            var received = 0L
                            while (true) {
                                val bytes = from.read(buffer)
                                if (bytes < 0) break
                                received += bytes
                                require(received <= offer.size)
                                digest.update(buffer, 0, bytes)
                                to.write(buffer, 0, bytes)
                                downloadProgress = (received * 100 / offer.size).toInt().coerceAtMost(99)
                            }
                            require(received == offer.size)
                        }
                    }
                } finally {
                    connection.disconnect()
                }
                if (digest.digest().hex() != offer.sha256 || !matchesPackage(c, partial, offer)) {
                    error = "verification"
                } else {
                    require(partial.renameTo(target))
                    prefs(c).edit().putString("verified", offer.sha256).apply()
                }
            } catch (_: Exception) {
                error = "download"
            } finally {
                partial.delete()
                downloadProgress = -1
            }
        }
    }

    fun install(c: Context): String {
        if (!BuildConfig.GITHUB_UPDATES) return "unavailable"
        val offer = release(c) ?: return "unavailable"
        if (!ready(c, offer)) return "unavailable"
        val current = apkFile(c, offer)
        val installer = if (c.packageManager.canRequestPackageInstalls()) {
            val uri = FileProvider.getUriForFile(c, c.packageName + ".updates", current)
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${c.packageName}"))
        }
        c.startActivity(installer)
        return if (installer.action == Intent.ACTION_VIEW) "installer" else "permission"
    }

    private fun apkFile(c: Context, offer: YawmiRelease) = File(c.cacheDir, "release-update/yawmi-${offer.version}.apk")
    private fun ready(c: Context, offer: YawmiRelease): Boolean = apkFile(c, offer).let {
        it.isFile && it.length() == offer.size && prefs(c).getString("verified", null) == offer.sha256
    }

    private fun connect(url: String, releaseApi: Boolean = false, etag: String? = null): HttpsURLConnection {
        var next = URI(url)
        repeat(5) {
            require(next.scheme == "https" && next.host in hosts && next.userInfo == null && next.port == -1)
            val connection = next.toURL().openConnection() as HttpsURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 12_000
            connection.readTimeout = 28_000
            connection.setRequestProperty("User-Agent", "Yawmi-Android-Updates")
            if (releaseApi) {
                connection.setRequestProperty("Accept", "application/vnd.github+json")
                if (etag != null) connection.setRequestProperty("If-None-Match", etag)
            }
            val status = try { connection.responseCode }
                catch (failure: IOException) { connection.disconnect(); throw failure }
            if (status !in setOf(301, 302, 303, 307, 308)) return connection
            val location = connection.getHeaderField("Location")
            connection.disconnect()
            next = next.resolve(location ?: throw IOException("Release redirect missing"))
        }
        throw IOException("Too many release redirects")
    }

    private fun notifyUpdate(c: Context, offer: YawmiRelease) {
        val manager = c.getSystemService(NotificationManager::class.java)
        val store = prefs(c)
        if (!manager.areNotificationsEnabled() || store.getString("announced", "") == offer.version) return
        val ar = store.getBoolean("arabic", false)
        val channel = "updates"
        manager.createNotificationChannel(NotificationChannel(
            channel, if (ar) "تحديثات يومي" else "Yawmi updates", NotificationManager.IMPORTANCE_DEFAULT
        ))
        if (manager.getNotificationChannel(channel).importance == NotificationManager.IMPORTANCE_NONE) return
        val ready = if (ar) "الإصدار ${offer.version} جاهز للتنزيل" else "Version ${offer.version} is ready to download"
        manager.notify(UPDATE_NOTICE, ReminderKind.UPDATE.notification(
            c, channel, ar, ReminderCopy(ready, ready), System.currentTimeMillis(),
        ).setContentIntent(appShortcut(c, "updates", "app-update"))
            .addAction(Notification.Action.Builder(
                null, if (ar) "حدّث دلوقتي" else "Update now",
                appShortcut(c, "updates/download", "download-update")
            ).build()).build())
        store.edit().putString("announced", offer.version).apply()
    }

    @Suppress("DEPRECATION")
    private fun signingFlag() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun matchesPackage(c: Context, file: File, offer: YawmiRelease): Boolean {
        val candidate = c.packageManager.getPackageArchiveInfo(file.absolutePath, signingFlag()) ?: return false
        val current = installed(c)
        fun version(info: PackageInfo) = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        fun signers(info: PackageInfo) =
            if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners.orEmpty().toSet()
            else info.signatures.orEmpty().toSet()
        val expected = signers(current)
        return candidate.packageName == current.packageName && candidate.versionName == offer.version &&
            version(candidate) > version(current) && expected.isNotEmpty() && expected == signers(candidate)
    }

    private fun ByteArray.hex() = joinToString("") { "%02x".format(java.util.Locale.ROOT, it.toInt() and 0xff) }
}
