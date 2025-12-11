package com.example.lumaray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lumaray/vpn"
    private val EVENT_CHANNEL = "lumaray/vpn/events"
    private val REQUEST_VPN = 1001
    private var pendingResult: MethodChannel.Result? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler(::handleMethodCall)
        
        // Setup event channel for VPN events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        
        // Set callback for VPN stop event
        LibboxVpnService.setOnVpnStoppedCallback {
            eventSink?.success("vpnStopped")
        }
    }

          private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
              when (call.method) {
                  "prepareVpn" -> prepareVpn(result)
                  "startVpn" -> {
                      val configPath = call.argument<String>("configPath")
                      val profileName = call.argument<String>("profileName")
                      val transport = call.argument<String>("transport")
                      if (configPath == null) {
                          result.error("args", "Missing configPath", null)
                          return
                      }
                      LibboxVpnService.start(this, configPath, profileName, transport)
                      result.success(true)
                  }
                  "stopVpn" -> {
                      LibboxVpnService.stop(this)
                      result.success(true)
                  }
                  "getStats" -> {
                      val stats = LibboxVpnService.getStats()
                      result.success(mapOf(
                          "upload" to stats.first,
                          "download" to stats.second,
                      ))
                  }
                  else -> {
                      // Handle events from native side (like onVpnStopped)
                      // These don't need a result
                      result.success(null)
                  }
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
