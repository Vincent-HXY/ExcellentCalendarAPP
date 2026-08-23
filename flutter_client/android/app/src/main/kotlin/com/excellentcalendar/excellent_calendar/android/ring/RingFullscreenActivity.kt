package com.excellentcalendar.excellent_calendar.android.ring

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors

class RingFullscreenActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var actionFeedback: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
        if (android.os.Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        render()
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun render() {
        val runtime = RingRuntimeProvider.get(applicationContext)
        val session = runtime.activeSession()
        if (session == null) {
            finish()
            return
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 48)
            addView(TextView(this@RingFullscreenActivity).apply {
                text = if (session.items.size == 1) "你有一个日程提醒" else "你有 ${session.items.size} 个日程提醒"
                textSize = 24f
            })
            actionFeedback?.let { feedback ->
                addView(TextView(this@RingFullscreenActivity).apply {
                    text = feedback
                    textSize = 16f
                })
            }
        }
        session.items.forEachIndexed { index, item ->
            root.addView(Button(this).apply {
                text = "完成提醒 ${index + 1}"
                setOnClickListener {
                    executor.execute {
                        runtime.completeFromNotification(item.deliveryId)
                        runOnUiThread(::render)
                    }
                }
            })
        }
        root.addView(Button(this).apply {
            text = "关闭全部"
            setOnClickListener {
                runtime.stopFromNotification(session.items.map { it.deliveryId })
                finish()
            }
        })
        root.addView(Button(this).apply {
            text = "稍后全部"
            setOnClickListener {
                executor.execute {
                    val result = runtime.snoozeFromNotification(session.items.map { it.deliveryId })
                    runOnUiThread {
                        actionFeedback = ringSnoozeFeedback(result)
                        if (runtime.activeSession() == null) {
                            actionFeedback?.let { feedback ->
                                Toast.makeText(this@RingFullscreenActivity, feedback, Toast.LENGTH_LONG).show()
                            }
                            finish()
                        } else {
                            render()
                        }
                    }
                }
            }
        })
        setContentView(root, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }
}
