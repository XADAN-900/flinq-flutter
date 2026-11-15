package com.xadan.flinq

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

/**
 * Video küçük resmi: MediaMetadataRetriever ile videodan tek kare alıp JPEG döndürür.
 * Video oynatıcı açmadığı için çok hafiftir (ızgaralarda onlarca video güvenle gösterilir).
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashSaver()
        super.onCreate(savedInstanceState)
    }

    /** Yakalanmamış bir hata uygulamayı kapatırsa raporu dosyaya yazar; sonraki açılışta gösterilir. */
    private fun installCrashSaver() {
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        if (prev is CrashSaver) return
        Thread.setDefaultUncaughtExceptionHandler(CrashSaver(filesDir, prev))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flinq/crash")
            .setMethodCallHandler { call, result ->
                val f = File(filesDir, "last_crash.txt")
                when (call.method) {
                    "get" -> result.success(if (f.exists()) f.readText() else null)
                    "clear" -> {
                        f.delete()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flinq/video_thumb")
            .setMethodCallHandler { call, result ->
                if (call.method != "frame") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path: String? = call.argument<String>("path")
                val maxWidth: Int = call.argument<Int>("maxWidth") ?: 360
                if (path == null) {
                    result.error("arg", "path missing", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    val bytes = extractFrame(path, maxWidth)
                    mainHandler.post { result.success(bytes) }
                }
            }
    }

    private fun extractFrame(path: String, maxWidth: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            var bmp: Bitmap? = retriever.getFrameAtTime(300000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            if (bmp == null) bmp = retriever.frameAtTime
            if (bmp == null) return null
            var out: Bitmap = bmp
            if (out.width > maxWidth && out.width > 0) {
                val h = maxOf(1, (out.height.toFloat() * maxWidth / out.width).toInt())
                val scaled = Bitmap.createScaledBitmap(out, maxWidth, h, true)
                if (scaled != out) out.recycle()
                out = scaled
            }
            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            out.recycle()
            return stream.toByteArray()
        } catch (e: Exception) {
            return null
        } catch (e: OutOfMemoryError) {
            return null
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
            }
        }
    }
}

class CrashSaver(
    private val dir: File,
    private val prev: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(t: Thread, e: Throwable) {
        try {
            File(dir, "last_crash.txt").writeText(
                "FlinQ çökme raporu\n${java.util.Date()}\nThread: ${t.name}\n\n${Log.getStackTraceString(e)}"
            )
        } catch (x: Exception) {
        }
        prev?.uncaughtException(t, e)
    }
}
