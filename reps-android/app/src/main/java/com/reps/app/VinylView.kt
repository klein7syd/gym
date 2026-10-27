package com.reps.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/** 黑胶唱片：纹路 + 荧光标签 + 旋转 */
class VinylView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    private val d = resources.displayMetrics.density

    private val discPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF121214.toInt() }
    private val groovePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f * d
        color = 0xFF26262A.toInt()
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFD7FF3E.toInt() }
    private val holePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF0B0B0C.toInt() }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF0B0B0C.toInt()
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
    }
    private val shinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f * d
        color = 0x18FFFFFF
    }
    private val oval = RectF()

    private var angle = 0f
    private var anim: ValueAnimator? = null
    private var playing = false

    fun setPlaying(p: Boolean) {
        if (p == playing) return
        playing = p
        if (p) start() else stop()
    }

    private fun start() {
        anim?.cancel()
        anim = ValueAnimator.ofFloat(angle, angle + 360f).apply {
            duration = 4200
            interpolator = LinearInterpolator()
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                angle = it.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stop() {
        anim?.cancel()
        anim = null
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val cx = w / 2f
        val cy = h / 2f
        val R = minOf(w, h) / 2f - 1.5f * d
        if (R <= 0) return

        canvas.save()
        canvas.rotate(angle, cx, cy)
        canvas.drawCircle(cx, cy, R, discPaint)

        var r = R * 0.40f
        while (r < R * 0.97f) {
            canvas.drawCircle(cx, cy, r, groovePaint)
            r += 3.0f * d
        }

        canvas.drawCircle(cx, cy, R * 0.34f, labelPaint)
        if (R > 26 * d) {
            textPaint.textSize = R * 0.15f
            canvas.drawText("REPS", cx, cy + textPaint.textSize * 0.35f, textPaint)
        }
        canvas.drawCircle(cx, cy, R * 0.035f, holePaint)
        canvas.restore()

        // 固定高光，制造唱片反光
        oval.set(cx - R * 0.92f, cy - R * 0.92f, cx + R * 0.92f, cy + R * 0.92f)
        canvas.drawArc(oval, 205f, 55f, false, shinePaint)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }
}
