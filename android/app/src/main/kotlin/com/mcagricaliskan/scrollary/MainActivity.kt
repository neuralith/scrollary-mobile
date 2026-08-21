package com.mcagricaliskan.scrollary

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // webread/device_storage: free-space + backup exclusion. Backup
        // exclusion is an iOS concern (NSURLIsExcludedFromBackupKey); on
        // Android it reports false and the Dart side treats that as "not
        // supported here", never as an error.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "webread/device_storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                // Total + available in one call, so the percentage the
                // Library shows is assembled from a single moment.
                "capacity" -> {
                    try {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(
                            mapOf(
                                "free" to stat.availableBytes,
                                "total" to stat.totalBytes,
                            ),
                        )
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "excludeFromBackup" -> result.success(false)
                else -> result.notImplemented()
            }
        }
    }
}
