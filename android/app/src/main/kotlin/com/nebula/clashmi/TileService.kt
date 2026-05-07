package com.nebula.clashmi

import android.app.ActivityManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import java.io.File

@RequiresApi(24)
class TileService : TileService() {
    companion object {
        private const val TAG = "ClashMiTileService"
        private const val SERVICE_FILE_NAME = "service.json"
        private const val SERVICE_CLASS_NAME =
                "com.cyenx.clashmi.clashmi_vpn_service.ClashMiVpnService"
        private const val ACTION_START = "com.cyenx.clashmi.clashmi_vpn_service.START"
        private const val ACTION_STOP = "com.cyenx.clashmi.clashmi_vpn_service.STOP"
        private const val ACTION_STATE_CHANGED =
                "com.cyenx.clashmi.clashmi_vpn_service.STATE_CHANGED"
        private const val EXTRA_STATE = "state"
    }

    private var receiverRegistered = false
    private val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(
                        context: Context,
                        intent: Intent,
                ) {
                    when (intent.action) {
                        ACTION_STATE_CHANGED -> {
                            val state = intent.getStringExtra(EXTRA_STATE)
                            writeLog("stateChanged state=$state")
                            when (state) {
                                "connecting",
                                "connected" -> updateTile(true)
                                "disconnecting",
                                "disconnected" -> updateTile(false)
                                else -> update()
                            }
                        }
                    }
                }
            }

    override fun onCreate() {
        if (!receiverRegistered) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intentFilter = IntentFilter()
                intentFilter.addAction(ACTION_STATE_CHANGED)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(receiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(receiver, intentFilter)
                }
                receiverRegistered = true
            }
        }
        super.onCreate()
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            receiverRegistered = false
            unregisterReceiver(receiver)
        }
        super.onDestroy()
    }

    override fun onClick() {
        if (isRuning()) {
            var intent = Intent().apply { action = ACTION_STOP }
            intent.setClassName(getPackageName(), SERVICE_CLASS_NAME)
            writeLog("onClick stop service")
            startService(intent)
            updateTile(false)
            return
        }

        try {
            writeLog("onClick start service")
            updateTile(true)
            startByService()
        } catch (e: Exception) {
            var stackTrace = e.getStackTrace().joinToString(separator = "\n")
            writeLog("onClick exception: $e \n$stackTrace")
            update()
        }
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        update()
    }

    override fun onStartListening() {
        super.onStartListening()
        update()
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    private fun isValid(): Boolean {
        return serviceFile().exists()
    }

    private fun update() {
        if (isRuning()) {
            updateTile(true)
            return
        }
        val valid = if (isValid()) false else null
        writeLog("update running=false valid=${valid != null}")
        updateTile(valid)
    }

    private fun updateTile(active: Boolean?) {
        qsTile?.apply {
            state =
                    when (active) {
                        true -> Tile.STATE_ACTIVE
                        false -> Tile.STATE_INACTIVE
                        else -> Tile.STATE_UNAVAILABLE
                    }
            writeLog("updateTile state=$state")
            updateTile()
        }
    }

    private fun startByService() {
        var intent = Intent().apply { action = ACTION_START }
        intent.setClassName(getPackageName(), SERVICE_CLASS_NAME)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun startByLaunch() {
        var intent = Intent()
        intent.setClassName(getPackageName(), MainActivity::class.java.name)
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.putExtra("command", "connect")
        if (Build.VERSION.SDK_INT < 34) {
            startActivityAndCollapse(intent)
        } else {
            startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
            )
        }
    }

    private fun startBy() {
        if (!isMainProcessRunning()) {
            startByLaunch()
        } else {
            startByService()
        }
    }

    private fun isMainRuning(): Boolean = isServiceRuning(MainActivity::class.java.name)

    private fun isRuning(): Boolean = isServiceRuning(SERVICE_CLASS_NAME)

    private fun isServiceRuning(serviceName: String): Boolean {
        try {
            val packageName = getPackageName()
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val services = activityManager.getRunningServices(Integer.MAX_VALUE)
            for (runningServiceInfo in services) {
                if (runningServiceInfo.service.getPackageName().equals(packageName)) {
                    if (runningServiceInfo.service.getClassName().equals(serviceName)) {
                        return runningServiceInfo.started
                    }
                }
            }
        } catch (e: Exception) {
            var stackTrace = e.getStackTrace().joinToString(separator = "\n")
            writeLog("isServiceRuning exception: $e \n$stackTrace")
        }

        return false
    }

    fun isMainProcessRunning(): Boolean {
        val packageName = getPackageName()
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val runningApps = activityManager.runningAppProcesses ?: return false
        for (procInfo in runningApps) {
            if (procInfo.processName == packageName) {
                return true
            }
        }
        return false
    }

    private fun serviceFile(): File {
        val context = this as Context
        return File(context.getFilesDir(), SERVICE_FILE_NAME)
    }

    private fun writeLog(message: String) {
        Log.i(TAG, message)
    }
}
