package com.xadan.flinq

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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
    companion object {
        /** Uygulama ekranda mı? (Ekrandayken arka plan servisi bildirim göstermez.) */
        @JvmField
        @Volatile
        var visible: Boolean = false
    }

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var nativeChannel: MethodChannel? = null
    private var pendingOpen: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installCrashSaver()
        super.onCreate(savedInstanceState)
        pendingOpen = target(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val t = target(intent) ?: return
        try {
            nativeChannel?.invokeMethod("open", t)
        } catch (e: Exception) {
        }
    }

    override fun onResume() {
        super.onResume()
        visible = true
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    /** Yerel bildirimden gelindiyse açılacak hedef: bildirim kimliği ya da "dm:<uid>". */
    private fun target(i: Intent?): String? {
        val id = i?.getStringExtra(FqNotify.EXTRA_ID) ?: return null
        return when (i.action) {
            FqNotify.ACTION_OPEN_NOTIF -> id
            FqNotify.ACTION_OPEN_DM -> "dm:$id"
            else -> null
        }
    }

    /** Yakalanmamış bir hata uygulamayı kapatırsa raporu dosyaya yazar; sonraki açılışta gösterilir. */
    private fun installCrashSaver() {
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        if (prev is CrashSaver) return
        Thread.setDefaultUncaughtExceptionHandler(CrashSaver(filesDir, prev))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val nc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flinq/native")
        nativeChannel = nc
        nc.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "setSession" -> {
                        FqSession.save(
                            this,
                            call.argument<String>("uid"),
                            call.argument<Boolean>("enabled") ?: true,
                            call.argument<Boolean>("sound") ?: true,
                            call.argument<Boolean>("preview") ?: true
                        )
                        FqNotify.createChannels(this)
                        FqService.ensureRunning(this)
                        FqWatcher.get(this).refresh()
                        result.success(true)
                    }
                    "clearSession" -> {
                        FqSession.clear(this)
                        FqService.stop(this)
                        result.success(true)
                    }
                    "takeLaunch" -> {
                        val p = pendingOpen
                        pendingOpen = null
                        result.success(p)
                    }
                    "isIgnoringBattery" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBattery" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
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
