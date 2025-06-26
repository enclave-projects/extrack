package com.example.extrack

import android.os.Build
import android.os.Bundle
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        
        // Check and request exact alarm permission on Android 13 and higher
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!alarmManager.canScheduleExactAlarms()) {
                try {
                    // Open settings to allow user to enable exact alarms permission
                    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    intent.data = Uri.fromParts("package", packageName, null)
                    startActivity(intent)
                } catch (e: Exception) {
                    // Log if there's an issue opening the settings
                    println("Failed to open exact alarm settings: ${e.message}")
                }
            }
        }
    }
}
