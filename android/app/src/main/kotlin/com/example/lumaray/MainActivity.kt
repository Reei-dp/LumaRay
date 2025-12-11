package com.example.lumaray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lumaray/vpn"
    private val REQUEST_VPN = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareVpn" -> prepareVpn(result)
            "startVpn" -> {
                val configPath = call.argument<String>("configPath")
                if (configPath == null) {
                    result.error("args", "Missing configPath", null)
                    return
                }
                LibboxVpnService.start(this, configPath)
                result.success(true)
            }
            "stopVpn" -> {
                LibboxVpnService.stop(this)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            startActivityForResult(intent, REQUEST_VPN)
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN) {
            val res = pendingResult
            pendingResult = null
            if (res != null) {
                res.success(resultCode == Activity.RESULT_OK)
                return
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
