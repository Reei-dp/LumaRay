package com.example.lumaray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import go.Seq
import io.nekohasekai.libbox.BoxService
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import java.io.File
import java.net.Inet6Address
import java.net.InterfaceAddress
import java.net.NetworkInterface

class LibboxVpnService : VpnService(), PlatformInterface {
    
    companion object {
        private const val TAG = "LibboxVpnService"
        private const val CHANNEL_ID = "lumaray_vpn_channel"
        private const val NOTIFICATION_ID = 101
        private const val EXTRA_CONFIG = "configPath"
        
        private var boxService: BoxService? = null
        private var fileDescriptor: ParcelFileDescriptor? = null
        
        fun start(context: Context, configPath: String) {
            val intent = Intent(context, LibboxVpnService::class.java).apply {
                putExtra(EXTRA_CONFIG, configPath)
            }
            Log.i(TAG, "Start service config=$configPath")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: Context) {
            boxService?.close()
            boxService = null
            fileDescriptor?.close()
            fileDescriptor = null
            context.stopService(Intent(context, LibboxVpnService::class.java))
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val configPath = intent?.getStringExtra(EXTRA_CONFIG)
        if (configPath.isNullOrEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        
        Log.i(TAG, "onStartCommand config=$configPath")
        startForeground(NOTIFICATION_ID, buildNotification())
        
        try {
            val configContent = File(configPath).readText()
            if (configContent.isBlank()) {
                Log.e(TAG, "Config is empty")
                stopSelf()
                return START_NOT_STICKY
            }
            
            // Initialize libbox
            Libbox.setup(io.nekohasekai.libbox.SetupOptions().apply {
                basePath = filesDir.path
                workingPath = getExternalFilesDir(null)?.path ?: filesDir.path
                tempPath = cacheDir.path
            })
            
            // Create service
            val newService = Libbox.newService(configContent, this)
            newService.start()
            
            boxService = newService
            Log.i(TAG, "Libbox service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start libbox service: ${e.message}", e)
            stopSelf()
        }
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        DefaultNetworkMonitor.setListener(null, null)
        boxService?.close()
        boxService = null
        fileDescriptor?.close()
        fileDescriptor = null
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    // PlatformInterface implementation
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    
    override fun autoDetectInterfaceControl(fd: Int) {
        try {
            protect(fd)
            Log.d(TAG, "Protected socket fd=$fd")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to protect socket fd=$fd: ${e.message}", e)
        }
    }
    
    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) {
            error("android: missing vpn permission")
        }
        
        val builder = Builder()
            .setSession("LumaRay VPN")
            .setMtu(options.mtu)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        
        // Add IPv4 addresses
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        
        // Add IPv6 addresses
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        
        // Add routes
        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress.value)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4RouteAddress = options.inet4RouteAddress
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val route = inet4RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    builder.addRoute("0.0.0.0", 0)
                }
                
                val inet6RouteAddress = options.inet6RouteAddress
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val route = inet6RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }
            } else {
                val inet4RouteAddress = options.inet4RouteRange
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val route = inet4RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                }
                
                val inet6RouteAddress = options.inet6RouteRange
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val route = inet6RouteAddress.next()
                        builder.addRoute(route.address(), route.prefix())
                    }
                }
            }
        }
        
        val pfd = builder.establish() ?: error("android: failed to establish VPN")
        fileDescriptor = pfd
        return pfd.fd
    }
    
    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
    
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int
    ): Int {
        // Simplified - return current UID
        return android.os.Process.myUid()
    }
    
    override fun packageNameByUid(uid: Int): String {
        return packageManager.getPackagesForUid(uid)?.firstOrNull() ?: error("android: package not found")
    }
    
    override fun uidByPackageName(packageName: String): Int {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageUid(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageUid(packageName, 0)
            }
        } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
            error("android: package not found")
        }
    }
    
    override fun startDefaultInterfaceMonitor(listener: io.nekohasekai.libbox.InterfaceUpdateListener) {
        Log.d(TAG, "startDefaultInterfaceMonitor called")
        DefaultNetworkMonitor.setListener(this, listener)
    }
    
    override fun closeDefaultInterfaceMonitor(listener: io.nekohasekai.libbox.InterfaceUpdateListener) {
        Log.d(TAG, "closeDefaultInterfaceMonitor called")
        DefaultNetworkMonitor.setListener(this, null)
    }
    
    override fun getInterfaces(): NetworkInterfaceIterator {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val networks = connectivityManager.allNetworks
        val networkInterfaces = NetworkInterface.getNetworkInterfaces().toList()
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        
        Log.d(TAG, "getInterfaces: found ${networks.size} networks, ${networkInterfaces.size} java interfaces")
        
        for (network in networks) {
            val linkProperties = connectivityManager.getLinkProperties(network) ?: continue
            val networkCapabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = linkProperties.interfaceName
            
            val javaInterface = networkInterfaces.find { it.name == boxInterface.name } ?: continue
            
            // DNS servers
            boxInterface.dnsServer = StringArray(linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator())
            
            // Interface type
            boxInterface.type = when {
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            
            boxInterface.index = javaInterface.index
            
            try {
                boxInterface.mtu = javaInterface.mtu
            } catch (e: Exception) {
                Log.w(TAG, "Failed to get MTU for ${boxInterface.name}: ${e.message}")
            }
            
            // Addresses
            boxInterface.addresses = StringArray(
                javaInterface.interfaceAddresses.mapTo(mutableListOf()) { it.toPrefix() }.iterator()
            )
            
            // Flags
            var dumpFlags = 0
            if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                dumpFlags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (javaInterface.isLoopback) {
                dumpFlags = dumpFlags or OsConstants.IFF_LOOPBACK
            }
            if (javaInterface.isPointToPoint) {
                dumpFlags = dumpFlags or OsConstants.IFF_POINTOPOINT
            }
            if (javaInterface.supportsMulticast()) {
                dumpFlags = dumpFlags or OsConstants.IFF_MULTICAST
            }
            boxInterface.flags = dumpFlags
            
            boxInterface.metered = !networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            
            interfaces.add(boxInterface)
            Log.d(TAG, "Added interface: ${boxInterface.name}, type=${boxInterface.type}, index=${boxInterface.index}")
        }
        
        Log.d(TAG, "getInterfaces: returning ${interfaces.size} interfaces")
        return InterfaceArray(interfaces.iterator())
    }
    
    private fun InterfaceAddress.toPrefix(): String {
        return if (address is Inet6Address) {
            "${Inet6Address.getByAddress(address.address).hostAddress}/${networkPrefixLength}"
        } else {
            "${address.hostAddress}/${networkPrefixLength}"
        }
    }
    
    private class InterfaceArray(private val iterator: Iterator<LibboxNetworkInterface>) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): LibboxNetworkInterface = iterator.next()
    }
    
    private class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }
    
    override fun underNetworkExtension(): Boolean = false
    
    override fun includeAllNetworks(): Boolean = false
    
    override fun clearDNSCache() {
        // Not needed
    }
    
    override fun readWIFIState(): io.nekohasekai.libbox.WIFIState? {
        // Simplified - return null
        return null
    }
    
    override fun localDNSTransport(): io.nekohasekai.libbox.LocalDNSTransport? {
        return LocalResolver
    }
    
    override fun systemCertificates(): io.nekohasekai.libbox.StringIterator {
        // Simplified - return empty iterator
        return object : io.nekohasekai.libbox.StringIterator {
            override fun len(): Int = 0
            override fun hasNext(): Boolean = false
            override fun next(): String = error("no more certificates")
        }
    }
    
    override fun writeLog(message: String) {
        Log.d(TAG, message)
    }
    
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
        // Update notification if needed
    }
    
    private fun buildNotification(): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "LumaRay VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            mgr.createNotificationChannel(channel)
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("LumaRay VPN")
            .setContentText("VPN подключение активно")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}

