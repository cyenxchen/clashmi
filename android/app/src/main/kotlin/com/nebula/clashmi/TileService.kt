package com.nebula.clashmi

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import com.cyenx.clashmi.clashmi_vpn_service.ClashmiVpnStatus
import com.cyenx.clashmi.clashmi_vpn_service.RotatingLogWriter
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

@RequiresApi(24)
class TileService : TileService() {
    companion object {
        private const val TAG = "ClashMiTileService"
        private const val SERVICE_FILE_NAME = "service.json"
        internal const val SERVICE_CLASS_NAME =
                "com.cyenx.clashmi.clashmi_vpn_service.ClashMiVpnService"
        internal const val ACTION_START = "com.cyenx.clashmi.clashmi_vpn_service.START"
        internal const val ACTION_STOP = "com.cyenx.clashmi.clashmi_vpn_service.STOP"
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
                                "connected" -> updateTile(true)
                                "disconnected" -> updateTile(false)
                                "connecting",
                                "disconnecting" -> updateTile(null)
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
        val state = ClashmiVpnStatus.currentState()
        writeLog("onClick state=$state validConfig=${isValid()}")
        when (state) {
            "connected",
            "connecting" -> {
                requestStop()
                // Keep the tile busy until the service broadcasts that native
                // cleanup and TUN release have actually finished.
                updateTile(null)
            }
            "disconnecting" -> {
                writeLog("onClick ignored while native stop is still running")
                updateTile(null)
            }
            "disconnected" -> requestStart()
            else -> {
                writeLog("onClick ignored unknownState=$state")
                update()
            }
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
        val state = ClashmiVpnStatus.currentState()
        val active = when (state) {
            "connected" -> true
            "disconnected" -> if (isValid()) false else null
            "connecting",
            "disconnecting" -> null
            else -> null
        }
        writeLog("update state=$state validConfig=${isValid()} active=$active")
        updateTile(active)
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
        val intent = Intent().apply { action = ACTION_START }
        intent.setClassName(getPackageName(), SERVICE_CLASS_NAME)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun startByLaunch() {
        // The app's existing scheme handler performs the normal profile and VPN
        // permission flow; the old "command" extra was never consumed.
        val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("clashmi://connect?background=true"),
        ).apply {
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT < 34) {
            startActivityAndCollapse(intent)
        } else {
            startActivityAndCollapse(
                    PendingIntent.getActivity(
                            this,
                            0,
                            intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
            )
        }
    }

    private fun requestStart() {
        if (!isValid()) {
            writeLog("start ignored: service config is missing")
            updateTile(null)
            return
        }
        try {
            if (VpnService.prepare(this) != null) {
                writeLog("start requires VPN permission; launching app flow")
                updateTile(null)
                startByLaunch()
                return
            }
            writeLog("start service intent")
            updateTile(null)
            startByService()
        } catch (error: Throwable) {
            writeLog("start failed: ${error.message}\n${Log.getStackTraceString(error)}")
            update()
        }
    }

    private fun requestStop() {
        try {
            val intent = Intent().apply { action = ACTION_STOP }
            intent.setClassName(getPackageName(), SERVICE_CLASS_NAME)
            writeLog("stop service intent")
            startService(intent)
        } catch (error: Throwable) {
            writeLog("stop failed: ${error.message}\n${Log.getStackTraceString(error)}")
            update()
        }
    }

    private fun serviceFile(): File {
        val context = this as Context
        return File(context.getFilesDir(), SERVICE_FILE_NAME)
    }

    private fun writeLog(message: String) {
        Log.i(TAG, message)
        // Persist tile evidence beside the core lifecycle log. Logcat commonly
        // rolls over before an intermittent quick-settings failure is reported.
        runCatching {
            val configFile = serviceFile()
            if (!configFile.exists()) {
                return@runCatching
            }
            val logPath = JSONObject(configFile.readText()).optString("log_path")
            if (logPath.isEmpty()) {
                return@runCatching
            }
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
            val rotated = RotatingLogWriter.append(
                    File(logPath),
                    "$timestamp [I] [ClashMiTileService] $message\n",
            )
            if (rotated) {
                Log.i(
                        TAG,
                        "persistent log rotated path=$logPath maxBytes=${RotatingLogWriter.MAX_FILE_BYTES} maxFiles=${RotatingLogWriter.MAX_FILE_COUNT}",
                )
            }
        }.onFailure {
            Log.w(TAG, "append tile log failed: ${it.message}")
        }
    }
}
