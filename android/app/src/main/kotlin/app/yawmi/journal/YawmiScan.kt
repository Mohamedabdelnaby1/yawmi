package app.yawmi.journal

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ScanFileProvider : FileProvider()

internal class YawmiScan(private val activity: Activity) {
    companion object { const val REQUEST = 8199 }

    private var cameraResult: MethodChannel.Result? = null
    private var cameraFile: File? = null

    fun capture(result: MethodChannel.Result) {
        if (cameraResult != null) {
            result.error("cameraBusy", "Camera already open", null)
            return
        }
        val directory = File(activity.cacheDir, "capture").apply { mkdirs() }
        directory.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86_400_000L }
            ?.forEach { it.delete() }
        val file = File.createTempFile("scan-", ".jpg", directory)
        try {
            val uri = FileProvider.getUriForFile(activity, activity.packageName + ".scan", file)
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                clipData = ClipData.newRawUri("photo", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            cameraFile = file
            cameraResult = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST)
        } catch (e: Exception) {
            cameraFile = null
            cameraResult = null
            file.delete()
            result.error("cameraUnavailable", "Could not open the camera", null)
        }
    }

    fun finished(resultCode: Int) {
        val pending = cameraResult ?: return
        val file = cameraFile
        cameraResult = null
        cameraFile = null
        if (resultCode != Activity.RESULT_OK || file == null) {
            file?.delete()
            pending.success(null)
            return
        }
        read(file, pending) { file.delete() }
    }

    fun readFile(path: String, result: MethodChannel.Result) {
        val selected = File(path).canonicalFile
        val root = activity.cacheDir.canonicalFile
        if (!selected.toPath().startsWith(root.toPath())) {
            result.error("scanPath", "The selected image is unavailable", null)
            return
        }
        read(selected, result)
    }

    private fun read(file: File, result: MethodChannel.Result, done: () -> Unit = {}) {
        try {
            require(file.isFile && file.length() in 1..16_000_000)
            val size = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, size)
            require(size.outWidth > 0 && size.outHeight > 0 &&
                size.outWidth.toLong() * size.outHeight <= 32_000_000L)
            val image = InputImage.fromFilePath(activity, Uri.fromFile(file))
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { result.success(it.text.take(16_000)) }
                .addOnFailureListener { result.error("textScan", "Could not read this photo", null) }
                .addOnCompleteListener { recognizer.close(); done() }
        } catch (_: Exception) {
            done()
            result.error("textScan", "Could not read this photo", null)
        }
    }
}
