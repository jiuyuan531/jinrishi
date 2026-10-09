package com.shen.jinrishi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jinrishi/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    getSharedPreferences(TodayWidgetProvider.PREFS, MODE_PRIVATE).edit()
                        .putString("title", call.argument<String>("title") ?: "今日事")
                        .putString("body", call.argument<String>("body") ?: "")
                        .putString("updated", call.argument<String>("updated") ?: "")
                        .apply()
                    val mgr = AppWidgetManager.getInstance(this)
                    val ids = mgr.getAppWidgetIds(ComponentName(this, TodayWidgetProvider::class.java))
                    val intent = Intent(this, TodayWidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
