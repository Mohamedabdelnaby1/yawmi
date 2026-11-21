package app.yawmi.journal

import org.json.JSONObject

internal const val PROJECT = "Mohamedabdelnaby1/yawmi"
private const val APK = "Yawmi-Android.apk"
private const val MAX_APK = 180L * 1024 * 1024
private val semanticVersion = Regex("""v?(0|[1-9]\d{0,6})\.(0|[1-9]\d{0,6})\.(0|[1-9]\d{0,6})""")
private val sha256Hex = Regex("[0-9a-f]{64}")

internal data class YawmiRelease(
    val version: String,
    val size: Long,
    val sha256: String,
    val notes: String,
) {
    val apkUrl get() = "https://github.com/$PROJECT/releases/download/v$version/$APK"

    fun toJson() = JSONObject().put("version", version).put("size", size)
        .put("sha256", sha256).put("notes", notes)

    companion object {
        fun read(json: JSONObject): YawmiRelease = YawmiRelease(
            json.getString("version"), json.getLong("size"), json.getString("sha256"),
            json.optString("notes")
        ).also {
            require(semanticVersion.matches(it.version) && !it.version.startsWith("v"))
            require(it.size in 1..MAX_APK && sha256Hex.matches(it.sha256))
        }

        fun fromGitHub(response: JSONObject, installed: String): YawmiRelease? {
            if (response.optBoolean("draft") || response.optBoolean("prerelease")) return null
            val tag = response.optString("tag_name")
            require(tag.startsWith("v") && semanticVersion.matches(tag))
            val version = tag.removePrefix("v")
            if (!newer(version, installed)) return null
            val assets = response.getJSONArray("assets")
            val apk = (0 until assets.length()).map(assets::getJSONObject)
                .single { it.optString("name") == APK && it.optString("state") == "uploaded" }
            val digest = apk.optString("digest")
            require(digest.startsWith("sha256:"))
            val candidate = read(JSONObject().put("version", version).put("size", apk.getLong("size"))
                .put("sha256", digest.removePrefix("sha256:"))
                .put("notes", response.optString("body").take(3200)))
            require(apk.optString("browser_download_url") == candidate.apkUrl)
            return candidate
        }
    }
}

internal fun newer(version: String, installed: String): Boolean {
    val incoming = semanticVersion.matchEntire(version)?.groupValues?.drop(1) ?: return false
    val current = semanticVersion.matchEntire(installed)?.groupValues?.drop(1) ?: return false
    for (i in incoming.indices) {
        val comparison = incoming[i].toInt().compareTo(current[i].toInt())
        if (comparison != 0) return comparison > 0
    }
    return false
}
