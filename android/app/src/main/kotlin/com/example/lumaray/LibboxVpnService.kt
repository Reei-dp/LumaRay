package com.example.lumaray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
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
        private const val EXTRA_PROFILE_NAME = "profileName"
        private const val EXTRA_TRANSPORT = "transport"
        
        private var boxService: BoxService? = null
        private var fileDescriptor: ParcelFileDescriptor? = null
        private var uploadBytes: Long = 0L
        private var downloadBytes: Long = 0L
        private var lastRxBytes: Long = 0L
        private var lastTxBytes: Long = 0L
        private var currentProfileName: String? = null
        private var currentTransport: String? = null
        private var serviceInstance: LibboxVpnService? = null
        private var onVpnStoppedCallback: (() -> Unit)? = null
        
        fun setOnVpnStoppedCallback(callback: (() -> Unit)?) {
            onVpnStoppedCallback = callback
        }
        
        fun start(context: Context, configPath: String, profileName: String? = null, transport: String? = null) {
            val intent = Intent(context, LibboxVpnService::class.java).apply {
                putExtra(EXTRA_CONFIG, configPath)
                putExtra(EXTRA_PROFILE_NAME, profileName)
                putExtra(EXTRA_TRANSPORT, transport)
            }
            Log.i(TAG, "Start service config=$configPath, profile=$profileName, transport=$transport")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun updateNotification(context: Context) {
            serviceInstance?.updateNotificationInternal()
        }
        
        fun stop(context: Context) {
            boxService?.close()
            boxService = null
            fileDescriptor?.close()
            fileDescriptor = null
            uploadBytes = 0L
            downloadBytes = 0L
            lastRxBytes = 0L
            lastTxBytes = 0L
            currentProfileName = null
            currentTransport = null
            context.stopService(Intent(context, LibboxVpnService::class.java))
            // Notify callback that VPN was stopped
            onVpnStoppedCallback?.invoke()
        }
        
        fun getStats(): Pair<Long, Long> {
            val service = boxService ?: return Pair(0L, 0L)
            return try {
                // Try to get stats from BoxService
                // BoxService might have a method to get statistics
                // If not available, we'll track manually
                Pair(uploadBytes, downloadBytes)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get stats: ${e.message}", e)
                Pair(uploadBytes, downloadBytes)
            }
        }
        
        fun updateStats(upload: Long, download: Long) {
            uploadBytes = upload
            downloadBytes = download
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP_VPN") {
            stop(this)
            return START_NOT_STICKY
        }
        
        val configPath = intent?.getStringExtra(EXTRA_CONFIG)
        if (configPath.isNullOrEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }
        
        currentProfileName = intent?.getStringExtra(EXTRA_PROFILE_NAME)
        currentTransport = intent?.getStringExtra(EXTRA_TRANSPORT)
        serviceInstance = this
        
        Log.i(TAG, "onStartCommand config=$configPath, profile=$currentProfileName, transport=$currentTransport")
        val notification = buildNotification()
        Log.d(TAG, "Starting foreground service with notification")
        startForeground(NOTIFICATION_ID, notification)
        
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
            
            // Start stats tracking
            startStatsTracking()
            
            Log.i(TAG, "Libbox service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start libbox service: ${e.message}", e)
            stopSelf()
        }
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        DefaultNetworkMonitor.setListener(null, null)
        stopStatsTracking()
        boxService?.close()
        boxService = null
        fileDescriptor?.close()
        fileDescriptor = null
        uploadBytes = 0L
        downloadBytes = 0L
        lastRxBytes = 0L
        lastTxBytes = 0L
        currentProfileName = null
        currentTransport = null
        serviceInstance = null
        super.onDestroy()
    }
    
    private var statsTrackingThread: Thread? = null
    private var isTrackingStats = false
    private var currentRxSpeed: Long = 0L
    private var currentTxSpeed: Long = 0L
    
    private fun startStatsTracking() {
        isTrackingStats = true
        val appUid = android.os.Process.myUid()
        statsTrackingThread = Thread {
            var lastUidRxBytes = TrafficStats.getUidRxBytes(appUid)
            var lastUidTxBytes = TrafficStats.getUidTxBytes(appUid)
            
            while (isTrackingStats) {
                try {
                    val service = boxService
                    if (service != null) {
                        // Use TrafficStats API - tracks all network traffic for this UID
                        // Since VPN service routes all traffic, this should give us VPN stats
                        val currentRxBytes = TrafficStats.getUidRxBytes(appUid)
                        val currentTxBytes = TrafficStats.getUidTxBytes(appUid)
                        
                        if (currentRxBytes != TrafficStats.UNSUPPORTED.toLong() && 
                            currentTxBytes != TrafficStats.UNSUPPORTED.toLong()) {
                            
                            // Calculate difference from last reading
                            val rxDiff = if (lastUidRxBytes > 0 && currentRxBytes >= lastUidRxBytes) {
                                currentRxBytes - lastUidRxBytes
                            } else {
                                0L
                            }
                            
                            val txDiff = if (lastUidTxBytes > 0 && currentTxBytes >= lastUidTxBytes) {
                                currentTxBytes - lastUidTxBytes
                            } else {
                                0L
                            }
                            
                            // Update cumulative stats
                            downloadBytes += rxDiff
                            uploadBytes += txDiff
                            
                            // Store current speed for notification
                            currentRxSpeed = rxDiff
                            currentTxSpeed = txDiff
                            
                            lastUidRxBytes = currentRxBytes
                            lastUidTxBytes = currentTxBytes
                            
                            // Update notification every second with new stats
                            updateNotificationInternal()
                            
                            Log.d(TAG, "Stats: upload=$uploadBytes, download=$downloadBytes (rx=$rxDiff, tx=$txDiff)")
                        } else {
                            Log.d(TAG, "TrafficStats not supported on this device")
                        }
                    }
                    Thread.sleep(1000) // Update every second
                } catch (e: InterruptedException) {
                    // Thread was interrupted, exit gracefully
                    Log.d(TAG, "Stats tracking thread interrupted, stopping")
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "Error in stats tracking: ${e.message}", e)
                }
            }
        }
        statsTrackingThread?.start()
    }
    
    
    private fun stopStatsTracking() {
        isTrackingStats = false
        statsTrackingThread?.interrupt()
        statsTrackingThread = null
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
    
    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) {
            return "$bytes Б"
        } else if (bytes < 1024 * 1024) {
            return String.format("%.2f кБ", bytes / 1024.0)
        } else if (bytes < 1024 * 1024 * 1024) {
            return String.format("%.2f МБ", bytes / (1024.0 * 1024.0))
        } else {
            return String.format("%.2f ГБ", bytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
    
    private fun formatSpeed(bytes: Long): String {
        if (bytes < 1024) {
            return "$bytes Б/с"
        } else if (bytes < 1024 * 1024) {
            return String.format("%.2f кБ/с", bytes / 1024.0)
        } else {
            return String.format("%.2f МБ/с", bytes / (1024.0 * 1024.0))
        }
    }
    
    private fun updateNotificationInternal() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification())
    }
    
    private fun buildNotification(): Notification {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Check if channel already exists
            val existingChannel = mgr.getNotificationChannel(CHANNEL_ID)
            if (existingChannel == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "LumaRay VPN",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
                channel.setShowBadge(false)
                channel.enableLights(false)
                channel.enableVibration(false)
                channel.setSound(null, null)
                channel.description = "Уведомления о статусе VPN подключения"
                channel.setShowBadge(false)
                mgr.createNotificationChannel(channel)
                Log.d(TAG, "Created notification channel: $CHANNEL_ID")
            } else {
                Log.d(TAG, "Notification channel already exists: $CHANNEL_ID")
            }
        }
        
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        val stopIntent = Intent(this, LibboxVpnService::class.java).apply {
            action = "STOP_VPN"
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        val profileName = currentProfileName ?: "Неизвестный конфиг"
        val transport = currentTransport?.uppercase() ?: "VLESS"
        
        // Title with total stats: "LumaRay • 3,06 кБ↑ 6,16 кБ↓"
        val titleText = "LumaRay • ${formatBytes(uploadBytes)}↑ ${formatBytes(downloadBytes)}↓"
        
        // Expanded content
        val expandedText = buildString {
            append(profileName)
            if (currentTransport != null) {
                append("\n[VLESS - $transport]")
            }
            append("\nПрокси : ${formatSpeed(currentTxSpeed)}↑ ${formatSpeed(currentRxSpeed)}↓")
        }
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(titleText)
            .setContentText(profileName)
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText(expandedText)
                .setSummaryText("VPN подключение активно"))
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Остановить",
                stopPendingIntent
            )
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .build()
        
        Log.d(TAG, "Built notification: title=$titleText, profile=$profileName")
        return notification
    }
}

