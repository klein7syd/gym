package com.reps.app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View

/** 组间计时环：底环 + 进度弧 + 中间大字 */
class TimerView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    private val d = resources.displayMetrics.density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 8f * d
        color = 0x14FFFFFF
    }

    private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 8f * d
        color = 0xFFD7FF3E.toInt()
        strokeCap = Paint.Cap.ROUND
    }

    private val bigPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFF2F0EA.toInt()
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
    }

    private val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF8A8A92.toInt()
        textAlign = Paint.Align.CENTER
    }

    private var progress = 1f
    private var big = "2:00"
    private var sub = "待开始"
    private val oval = RectF()

    fun update(leftMs: Long, totalMs: Long, label: String) {
        val total = if (totalMs <= 0) 1f else totalMs.toFloat()
        progress = (leftMs / total).coerceIn(0f, 1f)
        big = if (leftMs <= 0) "GO" else fmt(leftMs)
        sub = label
        invalidate()
    }

    fun setIdle(sec: Int, label: String) {
        progress = 1f
        big = fmt(sec * 1000L)
        sub = label
        invalidate()
    }

    private fun fmt(ms: Long): String {
        val s = (ms / 1000).coerceAtLeast(0)
        return String.format("%d:%02d", s / 60, s % 60)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val pad = 10f * d
        val size = minOf(w, h) - pad * 2
        val cx = w / 2f
        val cy = h / 2f
        oval.set(cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2)

        canvas.drawArc(oval, 0f, 360f, false, trackPaint)
        if (progress > 0f) canvas.drawArc(oval, -90f, 360f * progress, false, arcPaint)

        bigPaint.textSize = 46f * d
        canvas.drawText(big, cx, cy + 14f * d, bigPaint)

        subPaint.textSize = 10f * d
        canvas.drawText(sub, cx, cy + 40f * d, subPaint)
    }
}
