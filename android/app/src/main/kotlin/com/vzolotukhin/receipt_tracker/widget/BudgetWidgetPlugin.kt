package com.vzolotukhin.receipt_tracker.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Receives the current week from Dart and redraws the home screen widget.
 *
 * Dart sends finished strings. Money formatting lives in `formatCents` and
 * the week label in `week_math`, and a second implementation of either here
 * would be one more than can be kept in agreement — see decision 0019.
 *
 * The widget reads SharedPreferences rather than the database. It runs in a
 * different process on Android's schedule, and opening a SQLite file from two
 * processes to render a number is a lock-contention problem in exchange for
 * nothing. A snapshot is the right shape: the widget is a convenience
 * surface, the app is the source of truth.
 */
class BudgetWidgetPlugin : MethodChannel.MethodCallHandler {

    companion object {
        /** Matches `ChannelWidgetBridge.channelName`. Decision 0015. */
        const val CHANNEL = "receipt_tracker/widget"

        const val PREFS = "leafline_widget"
        const val KEY_WEEK = "weekLabel"
        const val KEY_SPENT = "spentText"
        const val KEY_BUDGET = "budgetText"
        const val KEY_STATUS = "statusText"
        const val KEY_PERCENT = "percent"
        const val KEY_OUTCOME = "outcome"
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.error("NOT_REGISTERED", "Plugin is not registered", null)
            return
        }

        when (call.method) {
            "update" -> {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_WEEK, call.argument<String>(KEY_WEEK).orEmpty())
                    .putString(KEY_SPENT, call.argument<String>(KEY_SPENT).orEmpty())
                    .putString(KEY_BUDGET, call.argument<String>(KEY_BUDGET).orEmpty())
                    .putString(KEY_STATUS, call.argument<String>(KEY_STATUS).orEmpty())
                    .putInt(KEY_PERCENT, call.argument<Int>(KEY_PERCENT) ?: 0)
                    .putString(KEY_OUTCOME, call.argument<String>(KEY_OUTCOME) ?: "noBudget")
                    .apply()

                notifyWidgets(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Asks every placed instance to redraw.
     *
     * An empty id array is the ordinary case — most people never place the
     * widget — and is not an error.
     */
    private fun notifyWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, BudgetWidgetProvider::class.java),
        )
        if (ids.isEmpty()) return
        BudgetWidgetProvider.render(context, manager, ids)
    }
}
