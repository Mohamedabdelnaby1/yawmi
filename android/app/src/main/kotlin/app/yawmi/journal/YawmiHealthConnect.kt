package app.yawmi.journal

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.health.connect.HealthConnectException
import android.health.connect.HealthConnectManager
import android.health.connect.ReadRecordsRequestUsingFilters
import android.health.connect.ReadRecordsResponse
import android.health.connect.TimeInstantRangeFilter
import android.health.connect.datatypes.BloodGlucoseRecord
import android.health.connect.datatypes.BloodPressureRecord
import android.health.connect.datatypes.InstantRecord
import android.os.Build
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.temporal.ChronoUnit

internal val healthReadPermissions = mapOf(
    "glucose" to "android.permission.health.READ_BLOOD_GLUCOSE",
    "pressure" to "android.permission.health.READ_BLOOD_PRESSURE",
)

internal fun healthGranted(activity: Activity): List<String> =
    healthReadPermissions.filterValues {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }.keys.toList()

@RequiresApi(34)
internal object YawmiHealthConnect {
    fun available(activity: Activity) =
        activity.getSystemService(HealthConnectManager::class.java) != null

    fun openPermissions(activity: Activity) {
        activity.startActivity(Intent(HealthConnectManager.ACTION_MANAGE_HEALTH_PERMISSIONS)
            .putExtra(Intent.EXTRA_PACKAGE_NAME, activity.packageName))
    }

    fun read(activity: Activity, requested: List<String>, result: MethodChannel.Result) {
        val manager = activity.getSystemService(HealthConnectManager::class.java)
        val selected = healthGranted(activity).filter(requested::contains)
        if (manager == null || selected.isEmpty()) {
            result.error("healthPermission", "No requested Health Connect access", null)
            return
        }
        val now = Instant.now()
        val range = TimeInstantRangeFilter.Builder()
            .setStartTime(now.minus(7, ChronoUnit.DAYS)).setEndTime(now).build()
        val entries = mutableListOf<Map<String, Any>>()

        fun <T : InstantRecord> readType(
            type: Class<T>, tracker: String, unit: String,
            values: (T) -> Map<String, Double>, done: () -> Unit, token: Long = -1,
        ) {
            val request = ReadRecordsRequestUsingFilters.Builder(type).setTimeRangeFilter(range)
                .setPageSize(500).apply { if (token != -1L) setPageToken(token) }.build()
            try {
                manager.readRecords(request, activity.mainExecutor, object :
                    OutcomeReceiver<ReadRecordsResponse<T>, HealthConnectException> {
                    override fun onResult(response: ReadRecordsResponse<T>) {
                        for (record in response.records) {
                            entries.add(mapOf(
                                "sourceRecordId" to "health-connect:$tracker:${record.metadata.id}",
                                "tracker" to tracker, "unit" to unit, "at" to record.time.toString(),
                                "values" to values(record),
                            ))
                        }
                        val next = response.nextPageToken
                        if (next != -1L && (entries.size >= 12000 || next == token)) {
                            result.error("healthLimit", "Health Connect returned too many entries", null)
                        } else if (next != -1L) {
                            readType(type, tracker, unit, values, done, next)
                        } else done()
                    }
                    override fun onError(error: HealthConnectException) {
                        result.error("healthRead", "Could not read Health Connect", null)
                    }
                })
            } catch (_: Exception) {
                result.error("healthRead", "Could not read Health Connect", null)
            }
        }

        fun readPressure() {
            if ("pressure" in selected) readType(
                BloodPressureRecord::class.java, "pressure", "mmHg",
                { record -> mapOf(
                    "systolic" to record.systolic.inMillimetersOfMercury,
                    "diastolic" to record.diastolic.inMillimetersOfMercury,
                ) },
                { result.success(entries) },
            ) else result.success(entries)
        }
        if ("glucose" in selected) readType(
            BloodGlucoseRecord::class.java, "glucose", "mmol/L",
            { record -> mapOf("value" to record.level.inMillimolesPerLiter) },
            ::readPressure,
        ) else readPressure()
    }
}
