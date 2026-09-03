package `in`.eike.better_stundenplan

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.lifecycleScope
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.annotations.SupabaseInternal
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.ktor.client.plugins.api.*
import io.ktor.client.request.*
import io.ktor.http.HttpHeaders
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.io.FileOutputStream

@Serializable
data class Homework(
    val subject: String,
    val content: String,
    val image_path: String? = null,
    val author_id: String
)

class MainActivity : FlutterFragmentActivity() {

    private lateinit var channel: MethodChannel

    @OptIn(SupabaseInternal::class)
    private val supabase: SupabaseClient by lazy {
        val publishableKey = "sb_publishable_5MmypUBhN-gDegkGC3PD1A_Oxvls8sF"
        createSupabaseClient(
            supabaseUrl = "https://znckapocehmwynnoekti.supabase.co",
            supabaseKey = publishableKey
        ) {
            install(Postgrest)
            install(Storage)
            httpConfig {
                install(createClientPlugin("StripAuthHeader") {
                    onRequest { request, _ ->
                        request.headers.remove(HttpHeaders.Authorization)
                    }
                })
            }
        }
    }

    private var pendingPictureResult: MethodChannel.Result? = null
    private var pendingPhotoUri: Uri? = null
    private var pendingPhotoPath: String? = null

    private val cameraLauncher = registerForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success ->
        if (success && pendingPhotoPath != null) {
            pendingPictureResult?.success(pendingPhotoPath)
        } else {
            pendingPictureResult?.success(null)
        }
        pendingPictureResult = null
        pendingPhotoUri = null
        pendingPhotoPath = null
    }

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            launchCamera()
        } else {
            pendingPictureResult?.success(null)
            pendingPictureResult = null
        }
    }

    private fun launchCamera() {
        val dir = File(cacheDir, "homework_pics")
        dir.mkdirs()
        val file = File(dir, "pic_${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        pendingPhotoUri = uri
        pendingPhotoPath = file.absolutePath
        cameraLauncher.launch(uri)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "in.eike.better_stundenplan/homework"
        )
        channel.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePicture" -> {
                pendingPictureResult = result
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                    == PackageManager.PERMISSION_GRANTED
                ) {
                    launchCamera()
                } else {
                    cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                }
            }

            "submitHomework" -> {
                val subject = call.argument<String>("subject") ?: ""
                val authorId = call.argument<String>("author_id") ?: ""
                val content = call.argument<String>("content") ?: ""
                val imagePath = call.argument<String>("image_path")

                if (subject.isEmpty()) {
                    result.error("MISSING_SUBJECT", "Fach erforderlich", null)
                    return
                }
                if (content.isEmpty()) {
                    result.error("EMPTY_CONTENT", "Beschreibung erforderlich", null)
                    return
                }

                lifecycleScope.launch(Dispatchers.IO) {
                    try {
                        var uploadedImageUrl: String? = null
                        if (imagePath != null) {
                            val file = File(imagePath)
                            if (file.exists()) {
                                val compressed = compressImage(file)
                                val bytes = compressed.readBytes()
                                val fileName = "${subject}_${System.currentTimeMillis()}.jpg"
                                supabase.storage.from("homework_images").upload(fileName, bytes)
                                uploadedImageUrl = supabase.storage.from("homework_images").publicUrl(fileName)
                            }
                        }

                        val homework = Homework(
                            subject = subject,
                            content = content,
                            image_path = uploadedImageUrl,
                            author_id = authorId
                        )
                        supabase.from("homework").insert(homework)

                        withContext(Dispatchers.Main) {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("UPLOAD_FAILED", e.message, null)
                        }
                    }
                }
            }

            "getHomework" -> {
                val subject = call.argument<String>("subject") ?: ""
                lifecycleScope.launch(Dispatchers.IO) {
                    try {
                        val homework = supabase.from("homework")
                            .select {
                                filter { eq("subject", subject) }
                                order("created_at", Order.DESCENDING)
                                limit(20)
                            }
                            .decodeList<Homework>()
                        result.success(homeworkToMaps(homework))
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("SUPABASE_ERROR", e.message, null)
                        }
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun compressImage(file: File): File {
        val maxDim = 2048
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)

        var sample = 1
        while (opts.outWidth / sample > maxDim || opts.outHeight / sample > maxDim) {
            sample *= 2
        }

        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bitmap = BitmapFactory.decodeFile(file.absolutePath, decodeOpts)
            ?: return file

        val rotation = try {
            val exif = ExifInterface(file.absolutePath)
            exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
        } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }

        val degrees = when (rotation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> {
                if (bitmap.width > bitmap.height * 1.5) 90f else 0f
            }
        }

        if (degrees != 0f) {
            val matrix = Matrix().apply { postRotate(degrees) }
            val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            bitmap.recycle()
            bitmap = rotated
        }

        val out = File(file.parent, "compressed_${file.name}")
        out.outputStream().use { fos ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, fos)
        }
        bitmap.recycle()
        return out
    }

    private fun homeworkToMaps(homework: List<Homework>): List<Map<String, String?>> {
        return homework.map { hw ->
            mapOf(
                "subject" to hw.subject,
                "content" to hw.content,
                "image_path" to hw.image_path,
                "author_id" to hw.author_id
            )
        }
    }
}
