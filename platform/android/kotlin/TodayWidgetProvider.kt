package com.shen.jinrishi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 桌面小组件：显示今日清单，点击打开应用。 */
class TodayWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(Date())
        val fresh = widgetData.getString("updated", "") == today
        val title = if (fresh) widgetData.getString("title", "今日事") else "今日事"
        val body = if (fresh) widgetData.getString("body", "") else "点一下加载今天的清单"
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.today_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_body, body)
                val pending = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
