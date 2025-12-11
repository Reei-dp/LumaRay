package com.example.lumaray

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

object DefaultNetworkMonitor {
    private var listener: InterfaceUpdateListener? = null
    private var connectivityManager: ConnectivityManager? = null
    private var defaultNetwork: Network? = null
    
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Log.d("DefaultNetworkMonitor", "Network available: $network")
            defaultNetwork = network
            checkDefaultInterfaceUpdate(network)
        }
        
        override fun onLost(network: Network) {
            Log.d("DefaultNetworkMonitor", "Network lost: $network")
            if (defaultNetwork == network) {
                defaultNetwork = null
            }
            checkDefaultInterfaceUpdate(null)
        }
        
        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            Log.d("DefaultNetworkMonitor", "Network capabilities changed: $network")
            if (defaultNetwork == network) {
                checkDefaultInterfaceUpdate(network)
            }
        }
    }
    
    fun setListener(context: Context?, newListener: InterfaceUpdateListener?) {
        val oldListener = listener
        listener = newListener
        
        if (oldListener == null && newListener != null) {
            // Start monitoring
            if (context != null) {
                connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val request = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
                connectivityManager?.registerNetworkCallback(request, networkCallback)
                
                // Get current default network
                defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    connectivityManager?.activeNetwork
                } else {
                    null
                }
                
                if (defaultNetwork != null) {
                    checkDefaultInterfaceUpdate(defaultNetwork)
                }
                
                Log.d("DefaultNetworkMonitor", "Started network monitoring, defaultNetwork=$defaultNetwork")
            }
        } else if (oldListener != null && newListener == null) {
            // Stop monitoring
            connectivityManager?.unregisterNetworkCallback(networkCallback)
            connectivityManager = null
            defaultNetwork = null
            Log.d("DefaultNetworkMonitor", "Stopped network monitoring")
        }
    }
    
    private fun checkDefaultInterfaceUpdate(network: Network?) {
        val listener = listener ?: return
        if (network != null && connectivityManager != null) {
            val linkProperties = connectivityManager!!.getLinkProperties(network) ?: return
            val interfaceName = linkProperties.interfaceName ?: return
            
            // Try to get interface index
            for (times in 0 until 10) {
                try {
                    val javaInterface = NetworkInterface.getByName(interfaceName)
                    if (javaInterface != null) {
                        val interfaceIndex = javaInterface.index
                        Log.d("DefaultNetworkMonitor", "Updating default interface: $interfaceName, index=$interfaceIndex")
                        listener.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
                        return
                    }
                } catch (e: Exception) {
                    Log.w("DefaultNetworkMonitor", "Failed to get interface $interfaceName, retry $times: ${e.message}")
                    if (times < 9) {
                        Thread.sleep(100)
                    }
                }
            }
        } else {
            Log.d("DefaultNetworkMonitor", "No default network, clearing interface")
            listener.updateDefaultInterface("", -1, false, false)
        }
    }
    
    fun require(): Network {
        if (defaultNetwork != null) {
            return defaultNetwork!!
        }
        // Try to get active network if defaultNetwork is null
        if (connectivityManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNetwork = connectivityManager!!.activeNetwork
            if (activeNetwork != null) {
                defaultNetwork = activeNetwork
                return activeNetwork
            }
        }
        throw IllegalStateException("No default network available")
    }
}

