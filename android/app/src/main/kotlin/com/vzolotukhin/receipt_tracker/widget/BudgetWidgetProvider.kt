package com.vzolotukhin.receipt_tracker.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.vzolotukhin.receipt_tracker.MainActivity
import com.vzolotukhin.receipt_tracker.R

/**
 * The home screen widget.
 *
 * Draws whatever snapshot Dart last pushed. It never queries anything — if
 * the app has not run since install, the layout's own defaults show, which
 * read as "open the app" rather than as an error.
 */
class BudgetWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context, appWidgetManager, appWidgetIds)
    }

    companion object {

        fun render(
            context: Context,
            manager: AppWidgetManager,
            ids: IntArray,
        ) {
            val prefs = context.getSharedPreferences(
                BudgetWidgetPlugin.PREFS,
                Context.MODE_PRIVATE,
            )

            val week = prefs.getString(BudgetWidgetPlugin.KEY_WEEK, null)
            val spent = prefs.getString(BudgetWidgetPlugin.KEY_SPENT, null)
            val budget = prefs.getString(BudgetWidgetPlugin.KEY_BUDGET, null)
            val status = prefs.getString(BudgetWidgetPlugin.KEY_STATUS, null)
            val percent = prefs.getInt(BudgetWidgetPlugin.KEY_PERCENT, 0)
            val outcome = prefs.getString(BudgetWidgetPlugin.KEY_OUTCOME, "noBudget")

            // Tapping anywhere opens the app. FLAG_IMMUTABLE is required from
            // API 31 and harmless before it.
            val tap = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val statusColour = when (outcome) {
                "over" -> R.color.widget_over
                "approaching" -> R.color.widget_approaching
                else -> R.color.widget_under
            }

            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.budget_widget)
                views.setTextViewText(
                    R.id.widget_week,
                    week ?: context.getString(R.string.widget_empty_week),
                )
                views.setTextViewText(R.id.widget_spent, spent ?: "\u2014")
                views.setTextViewText(R.id.widget_budget, budget.orEmpty())
                views.setTextViewText(
                    R.id.widget_status,
                    status ?: context.getString(R.string.widget_empty_status),
                )
                views.setTextColor(
                    R.id.widget_status,
                    context.getColor(statusColour),
                )
                views.setProgressBar(R.id.widget_progress, 100, percent, false)
                views.setOnClickPendingIntent(R.id.widget_root, tap)

                manager.updateAppWidget(id, views)
            }
        }
    }
}
