package app.cliplink.cliplink

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.cliplink/network",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(null)
                }

                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        try {
            val wifi =
                applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock =
                wifi.createMulticastLock("cliplink-discovery").apply {
                    setReferenceCounted(false)
                    acquire()
                }
        } catch (_: Exception) {
            // Broadcast discovery still works on most networks without the lock.
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.release()
        } catch (_: Exception) {
        } finally {
            multicastLock = null
        }
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
