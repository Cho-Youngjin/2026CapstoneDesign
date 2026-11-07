package com.travelfootsteps.device_probe

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 배터리 전하량·전류와 기기 정보를 읽는다. 엔진마다 붙으므로 포그라운드 서비스 isolate에서도 동작한다. */
class DeviceProbePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "device_probe")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "readBattery" -> result.success(readBattery())
            "readDevice" -> result.success(readDevice())
            else -> result.notImplemented()
        }
    }

    private fun readBattery(): Map<String, Any?> {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        // 지원하지 않는 속성은 Integer.MIN_VALUE를 돌려준다. null로 바꿔 Dart 쪽에서 '모름'으로 다룬다.
        fun property(id: Int): Int? = manager.getIntProperty(id).takeIf { it != Int.MIN_VALUE }

        // 수신기 없이(null) 등록하면 마지막 배터리 상태(sticky intent)만 읽고 끝난다.
        val sticky: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val temperature = sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0

        return mapOf(
            "chargeUah" to property(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),
            "currentUa" to property(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
            "levelPct" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "tempC" to if (temperature != Int.MIN_VALUE) temperature / 10.0 else null,
            "plugged" to (plugged != 0),
        )
    }

    private fun readDevice(): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "sdkInt" to Build.VERSION.SDK_INT,
            "appVersion" to info.versionName,
        )
    }
}
