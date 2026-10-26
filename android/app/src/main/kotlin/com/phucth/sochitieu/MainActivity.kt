package com.phucth.sochitieu

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Kênh "sochitieu/payment_apps": liệt kê ứng dụng đã cài (có biểu tượng trên màn hình chính),
 * đọc tên + biểu tượng một ứng dụng, và mở ứng dụng đó sau khi lưu khoản chi.
 * Chỉ cần <queries> MAIN/LAUNCHER trong AndroidManifest, không dùng QUERY_ALL_PACKAGES.
 */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sochitieu/payment_apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Đọc biểu tượng và nén PNG tốn thời gian: làm ở luồng phụ.
                    "listApps" -> background(result, emptyList<Map<String, Any?>>()) { listApps() }
                    "appInfo" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg.isNullOrEmpty()) result.success(null) else background(result, null) { appInfo(pkg) }
                    }
                    "launch" -> {
                        val pkg = call.argument<String>("package")
                        result.success(!pkg.isNullOrEmpty() && launch(pkg))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    /**
     * Chạy [work] ở luồng phụ rồi trả kết quả ở luồng chính. Luôn trả lời [result] đúng một lần:
     * lỗi bất kỳ (kể cả hết bộ nhớ khi vẽ biểu tượng) thành lỗi kênh; luồng phụ đã tắt (sau
     * onDestroy) thì trả [fallback].
     */
    private fun background(result: MethodChannel.Result, fallback: Any?, work: () -> Any?) {
        if (worker.isShutdown) {
            result.success(fallback)
            return
        }
        try {
            worker.execute {
                try {
                    val value = work()
                    main.post { result.success(value) }
                } catch (e: Throwable) {
                    main.post { result.error("payment_apps", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            result.success(fallback)
        }
    }

    private fun listApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()
        for (info in pm.queryIntentActivities(intent, 0)) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == packageName || !seen.add(pkg)) continue
            val label = info.loadLabel(pm)?.toString()?.trim().orEmpty().ifEmpty { pkg }
            val icon = try { png(info.loadIcon(pm)) } catch (e: Exception) { null }
            apps.add(mapOf("label" to label, "package" to pkg, "icon" to icon))
        }
        return apps.sortedBy { (it["label"] as String).lowercase() }
    }

    /** Tên + biểu tượng, hoặc null nếu ứng dụng không còn mở được. */
    private fun appInfo(pkg: String): Map<String, Any?>? {
        // Chính Sổ chi tiêu không phải ứng dụng thanh toán (listApps cũng bỏ qua nó).
        if (pkg == packageName) return null
        val pm = packageManager
        if (pm.getLaunchIntentForPackage(pkg) == null) return null
        return try {
            val app = pm.getApplicationInfo(pkg, 0)
            val label = pm.getApplicationLabel(app).toString().trim().ifEmpty { pkg }
            val icon = try { png(pm.getApplicationIcon(app)) } catch (e: Exception) { null }
            mapOf("label" to label, "package" to pkg, "icon" to icon)
        } catch (e: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun launch(pkg: String): Boolean {
        if (pkg == packageName) return false
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Vẽ biểu tượng (kể cả adaptive icon) ra ảnh vuông 96 px rồi nén PNG. Drawable của hệ thống
     * có thể dùng chung, nên trả lại kích thước cũ sau khi vẽ.
     */
    private fun png(drawable: Drawable): ByteArray {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val oldBounds = drawable.copyBounds()
        try {
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
        } finally {
            drawable.bounds = oldBounds
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }
}
