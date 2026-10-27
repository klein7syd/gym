package com.reps.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var tvDate: TextView
    private lateinit var tvExName: TextView
    private lateinit var tvLast: TextView
    private lateinit var tvW: TextView
    private lateinit var tvR: TextView
    private lateinit var setList: LinearLayout
    private lateinit var timerView: TimerView
    private lateinit var btnSkip: TextView
    private lateinit var statsBox: LinearLayout
    private lateinit var libBox: LinearLayout

    private lateinit var pageTrain: View
    private lateinit var pageStats: View
    private lateinit var pageLib: View
    private lateinit var tabTrain: TextView
    private lateinit var tabStats: TextView
    private lateinit var tabLib: TextView

    private lateinit var vinylMini: VinylView
    private lateinit var vinylBig: VinylView
    private lateinit var tvTrack: TextView
    private lateinit var tvTrackSub: TextView
    private lateinit var btnPlay: TextView
    private lateinit var btnPlay2: TextView
    private lateinit var tvSheetName: TextView
    private lateinit var tvSheetSub: TextView
    private lateinit var sheet: View
    private lateinit var seek: SeekBar

    private val main = Handler(Looper.getMainLooper())
    private var dragging = false

    private val pickMusic = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris: List<Uri>? ->
        if (uris.isNullOrEmpty()) return@registerForActivityResult
        uris.forEach { u ->
            try {
                contentResolver.takePersistableUriPermission(u, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: Exception) {
            }
        }
        Store.trackUri = uris.firstOrNull()?.toString() ?: ""
        Store.save()
        MusicService.play(this, uris, 0)
        main.postDelayed({ updatePlayerUI() }, 400)
    }

    private val askNotif = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Store.init(this)
        MoveLib.load(this)
        setContentView(R.layout.activity_main)
        bind()
        setupTabs()
        setupSteppers()
        setupChips()
        setupPlayer()
        renderDate()
        renderTrain()
        renderLib()
        renderStats()

        val libSearch = findViewById<android.widget.EditText>(R.id.libSearch)
        libSearch.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(sq: CharSequence?, st: Int, c: Int, a: Int) {}
            override fun onTextChanged(sq: CharSequence?, st: Int, b: Int, c: Int) { renderLib(sq?.toString() ?: "") }
            override fun afterTextChanged(ed: android.text.Editable?) {}
        })

        RestService.onTick = { left, total ->
            main.post {
                timerView.update(left, total, if (left > 0) "恢复中" else "开始下一组")
                btnSkip.visibility = if (left > 0) View.VISIBLE else View.GONE
            }
        }
        RestService.onDone = { main.post { timerView.update(0, RestService.totalMs, "开始下一组") } }

        if (RestService.running) {
            timerView.update(RestService.remainingMs, RestService.totalMs, "恢复中")
        } else {
            timerView.setIdle(Store.restSec, "待开始")
        }

        MusicService.onChange = { main.post { updatePlayerUI() } }
        updatePlayerUI()
        updateChips()
        askNotification()

        if (Store.trackUri.isNotBlank() && MusicService.list.isEmpty()) {
            tvTrackSub.text = "上次播放过的歌还在，点 ▶ 继续"
        }
    }

    // ---------------- 绑定 ----------------
    private fun bind() {
        tvDate = findViewById(R.id.tvDate)
        tvExName = findViewById(R.id.tvExName)
        tvLast = findViewById(R.id.tvLast)
        tvW = findViewById(R.id.tvW)
        tvR = findViewById(R.id.tvR)
        setList = findViewById(R.id.setList)
        timerView = findViewById(R.id.timerView)
        btnSkip = findViewById(R.id.btnSkip)
        statsBox = findViewById(R.id.statsBox)
        libBox = findViewById(R.id.libBox)
        pageTrain = findViewById(R.id.pageTrain)
        pageStats = findViewById(R.id.pageStats)
        pageLib = findViewById(R.id.pageLib)
        tabTrain = findViewById(R.id.tabTrain)
        tabStats = findViewById(R.id.tabStats)
        tabLib = findViewById(R.id.tabLib)
        vinylMini = findViewById(R.id.vinylMini)
        vinylBig = findViewById(R.id.vinylBig)
        tvTrack = findViewById(R.id.tvTrack)
        tvTrackSub = findViewById(R.id.tvTrackSub)
        btnPlay = findViewById(R.id.btnPlay)
        btnPlay2 = findViewById(R.id.btnPlay2)
        tvSheetName = findViewById(R.id.tvSheetName)
        tvSheetSub = findViewById(R.id.tvSheetSub)
        sheet = findViewById(R.id.sheet)
        seek = findViewById(R.id.seek)
    }

    // ---------------- 头部 ----------------
    private fun renderDate() {
        val d = Calendar.getInstance()
        val wk = arrayOf("周日", "周一", "周二", "周三", "周四", "周五", "周六")[d.get(Calendar.DAY_OF_WEEK) - 1]
        tvDate.text = "${d.get(Calendar.MONTH) + 1}月${d.get(Calendar.DAY_OF_MONTH)}日 · $wk"
    }

    // ---------------- tab ----------------
    private fun setupTabs() {
        tabTrain.setOnClickListener { showTab(0) }
        tabStats.setOnClickListener { showTab(1) }
        tabLib.setOnClickListener { showTab(2) }
        findViewById<TextView>(R.id.btnFinish).setOnClickListener { confirmFinish() }
        findViewById<TextView>(R.id.btnChange).setOnClickListener {
            showTab(2)
            toast("点一个动作设为当前")
        }
    }

    private fun showTab(i: Int) {
        pageTrain.visibility = if (i == 0) View.VISIBLE else View.GONE
        pageStats.visibility = if (i == 1) View.VISIBLE else View.GONE
        pageLib.visibility = if (i == 2) View.VISIBLE else View.GONE
        val on = ContextCompat.getDrawable(this, R.drawable.bg_tab_on)
        tabTrain.background = if (i == 0) on else null
        tabStats.background = if (i == 1) on else null
        tabLib.background = if (i == 2) on else null
        tabTrain.setTextColor(if (i == 0) 0xFFF2F0EA.toInt() else 0xFF8A8A92.toInt())
        tabStats.setTextColor(if (i == 1) 0xFFF2F0EA.toInt() else 0xFF8A8A92.toInt())
        tabLib.setTextColor(if (i == 2) 0xFFF2F0EA.toInt() else 0xFF8A8A92.toInt())
        if (i == 1) renderStats()
        if (i == 2) renderLib()
    }

    // ---------------- 训练页 ----------------
    private fun setupSteppers() {
        findViewById<TextView>(R.id.btnWMinus).setOnClickListener { Store.w = (Store.w - 2.5).coerceAtLeast(0.0); Store.save(); renderTrain() }
        findViewById<TextView>(R.id.btnWPlus).setOnClickListener { Store.w += 2.5; Store.save(); renderTrain() }
        findViewById<TextView>(R.id.btnRMinus).setOnClickListener { Store.r = (Store.r - 1).coerceAtLeast(1); Store.save(); renderTrain() }
        findViewById<TextView>(R.id.btnRPlus).setOnClickListener { Store.r += 1; Store.save(); renderTrain() }
        findViewById<TextView>(R.id.btnAddSet).setOnClickListener { addSet() }
        btnSkip.setOnClickListener {
            RestService.stop(this)
            timerView.update(0, 1, "开始下一组")
            btnSkip.visibility = View.GONE
        }
    }

    private fun renderTrain() {
        val ex = Store.currentEx()
        tvExName.text = ex.name
        tvW.text = fmtWeight(Store.w)
        tvR.text = Store.r.toString()

        val hist = Store.historyOf(ex.name).filter { h -> h.second !== ex.sets }
        if (hist.isNotEmpty()) {
            val sets = hist.last().second
            val maxW = sets.maxOf { it.w }
            val best = sets.maxOf { Store.e1rm(it.w, it.r) }
            tvLast.text = "上次 ${sets.size} 组 · 最重 ${fmtWeight(maxW)}kg · 估算 1RM ${String.format(Locale.US, "%.1f", best)}kg"
        } else {
            tvLast.text = "还没记录过这个动作，先找能做完 8-12 次的重量"
        }

        setList.removeAllViews()
        ex.sets.forEachIndexed { i, s ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(9), 0, dp(9))
            }
            row.addView(txt("${i + 1}", 12, 0xFF5C5C64.toInt(), 22))
            row.addView(txt("${fmtWeight(s.w)} kg × ${s.r}", 15, 0xFFF2F0EA.toInt(), 0, 1f))
            row.addView(txt("e1RM ${String.format(Locale.US, "%.1f", Store.e1rm(s.w, s.r))}", 12, 0xFF5C5C64.toInt(), 0))
            row.addView(txt("✓", 14, 0xFFD7FF3E.toInt(), 0))
            setList.addView(row)
        }
    }

    private fun addSet() {
        val ex = Store.currentEx()
        ex.sets.add(Store.SetRec(Store.w, Store.r, System.currentTimeMillis()))
        Store.save()
        renderTrain()
        RestService.start(this, Store.restSec)
        toast("已记录 · 开始休息 ${Store.restSec}s")
    }

    private fun confirmFinish() {
        val s = Store.cur
        if (s == null || s.exercises.none { it.sets.isNotEmpty() }) {
            toast("还没有记录，先练一组")
            return
        }
        AlertDialog.Builder(this)
            .setMessage("结束本次训练并保存？")
            .setNegativeButton("再练会儿", null)
            .setPositiveButton("保存") { _, _ ->
                if (Store.finishSession()) {
                    renderTrain()
                    renderStats()
                    toast("已保存")
                }
            }
            .show()
    }

    // ---------------- 计时 chip ----------------
    private fun setupChips() {
        listOf(R.id.chip60 to 60, R.id.chip90 to 90, R.id.chip120 to 120, R.id.chip180 to 180).forEach { (id, sec) ->
            findViewById<TextView>(id).setOnClickListener {
                Store.restSec = sec
                Store.save()
                updateChips()
                if (!RestService.running) timerView.setIdle(sec, "待开始")
            }
        }
    }

    private fun updateChips() {
        val onBg = ContextCompat.getDrawable(this, R.drawable.bg_chip_on)
        val offBg = ContextCompat.getDrawable(this, R.drawable.bg_chip)
        listOf(R.id.chip60 to 60, R.id.chip90 to 90, R.id.chip120 to 120, R.id.chip180 to 180).forEach { (id, sec) ->
            val v = findViewById<TextView>(id)
            val on = sec == Store.restSec
            v.background = if (on) onBg else offBg
            v.setTextColor(if (on) 0xFF0B0B0C.toInt() else 0xFF8A8A92.toInt())
        }
    }

    // ---------------- 进度页 ----------------
    private fun renderStats() {
        statsBox.removeAllViews()
        val names = mutableListOf<String>()
        Store.sessions.forEach { s -> s.exercises.forEach { e -> if (!names.contains(e.name)) names.add(e.name) } }

        if (names.isEmpty()) {
            statsBox.addView(txt("还没有完成的训练\n\n训练页做完一组、点「结束」保存后\n这里会出现你的每一次进步", 14, 0xFF5C5C64.toInt(), 0).apply {
                gravity = Gravity.CENTER
                setPadding(0, dp(60), 0, dp(60))
            })
            return
        }

        names.sortByDescending { nm ->
            Store.historyOf(nm).lastOrNull()?.first ?: 0L
        }

        val wk = Store.weekCapacity()
        if (wk > 0) {
            val card = card()
            card.addView(label("本周总容量"))
            card.addView(txt(String.format(Locale.US, "%,d", wk) + " kg", 34, 0xFFF2F0EA.toInt(), 0).apply {
                setPadding(0, dp(6), 0, dp(10))
            })
            card.addView(advice("容量 = 重量 × 次数 × 组数。想变强，先保证每周总容量不掉，再谈加重。"))
            statsBox.addView(card)
        }

        names.forEach { nm ->
            val h = Store.historyOf(nm)
            val e1s = h.map { p -> p.second.maxOf { Store.e1rm(it.w, it.r) } }
            val cur = e1s.lastOrNull() ?: 0.0
            val prev = if (e1s.size > 1) e1s[e1s.size - 2] else null
            val totalSets = h.sumOf { it.second.size }

            val card = card()
            val top = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            top.addView(txt(nm, 17, 0xFFF2F0EA.toInt(), 0, 1f).apply { setTypeface(typeface, android.graphics.Typeface.BOLD) })
            top.addView(txt(String.format(Locale.US, "%.1f", cur), 15, 0xFFD7FF3E.toInt(), 0).apply {
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            card.addView(top)

            val sub = "${h.size} 次训练 · $totalSets 组"
            if (prev != null) {
                val dlt = cur - prev
                sub.plus(if (dlt >= 0) "  ▲ ${String.format(Locale.US, "%.1f", dlt)}" else "  ▼ ${String.format(Locale.US, "%.1f", -dlt)}")
            }
            card.addView(txt(sub, 12, 0xFF5C5C64.toInt(), 0).apply { setPadding(0, dp(6), 0, dp(10)) })
            card.addView(advice(suggest(h.map { it.second })))
            statsBox.addView(card)
        }
    }

    private fun suggest(hist: List<List<Store.SetRec>>): String {
        val last = hist.lastOrNull() ?: return "第一次做，先找 8-12 次力竭前的重量"
        if (last.isEmpty()) return "第一次做，先找 8-12 次力竭前的重量"
        val maxR = last.maxOf { it.r }
        val n = last.size
        return when {
            maxR >= 12 && n >= 3 -> "$n 组全到 12 次 → 下次 +2.5kg，次数回到 8-10 次"
            maxR >= 10 && n >= 3 -> "已摸到 10 次 → 同重量再挤 1-2 次，稳了再加 1.25kg"
            n < 3 -> "只做了 $n 组 → 先把组数补到 3-4 组"
            else -> "次数还没到 10 → 同一重量继续堆次数，别急着加重"
        }
    }

    // ---------------- 动作库 ----------------
    private fun renderLib(q: String = "") {
        libBox.removeAllViews()
        if (q.isNotBlank()) {
            val hits = MoveLib.search(q)
            if (hits.isEmpty()) {
                libBox.addView(txt("没找到「$q」\n\n库里暂时没有这个动作\n把教学视频发企微给我，我拆成要领卡加进来", 14, 0xFF5C5C64.toInt(), 0).apply {
                    gravity = Gravity.CENTER
                    setPadding(0, dp(50), 0, dp(20))
                })
                return
            }
            libBox.addView(txt("找到 ${hits.size} 个", 11, 0xFF5C5C64.toInt(), 0).apply {
                letterSpacing = 0.16f
                setPadding(0, 0, 0, dp(10))
            })
            addPillRows(hits.map { it.n })
            return
        }

        val groups = linkedMapOf<String, MutableList<String>>()
        if (MoveLib.all.isNotEmpty()) MoveLib.all.forEach { groups.getOrPut(it.g) { mutableListOf() }.add(it.n) }
        Store.lib.forEach { (g, n) -> if (MoveLib.find(n) == null) groups.getOrPut(g) { mutableListOf() }.add(n) }

        groups.forEach { (g, list) ->
            libBox.addView(txt("$g  ${list.size}", 11, 0xFF5C5C64.toInt(), 0).apply {
                letterSpacing = 0.16f
                setPadding(0, dp(10), 0, dp(8))
            })
            addPillRows(list)
        }
    }

    private fun addPillRows(names: List<String>) {
        val wrap = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        var line: LinearLayout? = null
        names.forEachIndexed { i, n ->
            if (i % 3 == 0) {
                val l = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(0, 0, 0, dp(8))
                }
                wrap.addView(l)
                line = l
            }
            val pill = txt(n, 13, 0xFFF2F0EA.toInt(), 0)
            pill.setBackgroundResource(R.drawable.bg_pill)
            pill.setPadding(dp(8), dp(10), dp(8), dp(10))
            pill.gravity = Gravity.CENTER
            pill.isSingleLine = true
            pill.ellipsize = android.text.TextUtils.TruncateAt.END
            val lp = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            lp.marginEnd = dp(8)
            pill.layoutParams = lp
            pill.setOnClickListener { showMove(n) }
            line?.addView(pill)
        }
        libBox.addView(wrap)
    }

    private fun showMove(name: String) {
        val m = MoveLib.find(name)
        if (m == null) { pickExercise(name); return }
        val sb = StringBuilder()
        if (m.en.isNotBlank()) sb.append(m.en).append("\n\n")
        sb.append("目标肌：").append(m.mus).append("\n\n要领\n")
        m.cue.forEachIndexed { i, c -> sb.append(i + 1).append(". ").append(c).append("\n") }
        sb.append("\n常见错误\n")
        m.err.forEach { c -> sb.append("· ").append(c).append("\n") }
        if (m.alt.isNotEmpty()) sb.append("\n替代：").append(m.alt.joinToString(" / "))
        AlertDialog.Builder(this)
            .setTitle(m.n + "  ·  " + m.g + "/" + m.eq + "/" + m.p)
            .setMessage(sb.toString())
            .setPositiveButton("设为当前动作") { _, _ -> pickExercise(name) }
            .setNegativeButton("关闭", null)
            .show()
    }

    private fun pickExercise(name: String) {
        val s = Store.ensureSession()
        var idx = s.exercises.indexOfFirst { it.name == name }
        if (idx < 0) {
            s.exercises.add(Store.Ex(name))
            idx = s.exercises.size - 1
        }
        Store.curIdx = idx
        Store.save()
        renderTrain()
        showTab(0)
        toast("当前动作：$name")
    }

    // ---------------- 播放器 ----------------
    private fun setupPlayer() {
        btnPlay.setOnClickListener { onPlayTap() }
        btnPlay2.setOnClickListener { onPlayTap() }
        findViewById<TextView>(R.id.btnNext).setOnClickListener { MusicService.next(this); main.postDelayed({ updatePlayerUI() }, 250) }
        findViewById<TextView>(R.id.btnPrev).setOnClickListener { MusicService.prev(this); main.postDelayed({ updatePlayerUI() }, 250) }
        findViewById<TextView>(R.id.btnPickMusic).setOnClickListener { pickMusic.launch(arrayOf("audio/*")) }
        findViewById<TextView>(R.id.btnSheetClose).setOnClickListener { sheet.visibility = View.GONE }

        vinylMini.setOnClickListener { sheet.visibility = View.VISIBLE }
        vinylMini.setOnLongClickListener {
            pickMusic.launch(arrayOf("audio/*"))
            true
        }

        tvTrack.setOnClickListener { sheet.visibility = View.VISIBLE }

        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && dragging) tvSheetSub.text = fmtMs(progress) + " / " + fmtMs(MusicService.duration())
            }

            override fun onStartTrackingTouch(sb: SeekBar?) { dragging = true }
            override fun onStopTrackingTouch(sb: SeekBar?) {
                dragging = false
                MusicService.seek(sb?.progress ?: 0)
            }
        })

        main.post(object : Runnable {
            override fun run() {
                if (sheet.visibility == View.VISIBLE && !dragging) {
                    val d = MusicService.duration()
                    val p = MusicService.position()
                    if (d > 0) {
                        seek.max = d
                        seek.progress = p
                        tvSheetSub.text = "${fmtMs(p)} / ${fmtMs(d)}"
                    }
                }
                main.postDelayed(this, 600)
            }
        })
    }

    private fun onPlayTap() {
        if (MusicService.list.isEmpty() && Store.trackUri.isNotBlank()) {
            val u = Uri.parse(Store.trackUri)
            MusicService.play(this, listOf(u), 0)
            main.postDelayed({ updatePlayerUI() }, 500)
            return
        }
        if (MusicService.list.isEmpty()) {
            pickMusic.launch(arrayOf("audio/*"))
            return
        }
        MusicService.toggle(this)
        main.postDelayed({ updatePlayerUI() }, 200)
    }

    private fun updatePlayerUI() {
        val p = MusicService.playing
        btnPlay.text = if (p) "❚❚" else "▶"
        btnPlay2.text = if (p) "❚❚" else "▶"
        vinylMini.setPlaying(p)
        vinylBig.setPlaying(p)
        val name = MusicService.trackName.ifBlank { "还没放歌" }
        tvTrack.text = name
        tvSheetName.text = name
        tvTrackSub.text = if (MusicService.list.isEmpty()) "点黑胶选文件（长按直接选）" else "${MusicService.index + 1} / ${MusicService.list.size}"
        if (p) tvSheetSub.text = "黑胶播放中"
    }

    // ---------------- 工具 ----------------
    private fun askNotification() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                askNotif.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun fmtWeight(w: Double): String =
        if (w == w.toInt().toDouble()) w.toInt().toString() else String.format(Locale.US, "%.1f", w)

    private fun fmtMs(ms: Int): String {
        val s = ms / 1000
        return String.format(Locale.US, "%d:%02d", s / 60, s % 60)
    }

    private fun txt(t: String, size: Int, color: Int, widthDp: Int = 0, weight: Float = 0f): TextView {
        val v = TextView(this)
        v.text = t
        v.textSize = size.toFloat()
        v.setTextColor(color)
        v.includeFontPadding = false
        if (weight > 0f) {
            v.layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, weight)
        } else if (widthDp > 0) {
            v.layoutParams = LinearLayout.LayoutParams(dp(widthDp), LinearLayout.LayoutParams.WRAP_CONTENT)
        }
        return v
    }

    private fun label(t: String): TextView = txt(t, 11, 0xFF5C5C64.toInt(), 0).apply { letterSpacing = 0.16f }

    private fun card(): LinearLayout {
        val c = LinearLayout(this)
        c.orientation = LinearLayout.VERTICAL
        c.setBackgroundResource(R.drawable.bg_card)
        c.setPadding(dp(20), dp(18), dp(20), dp(18))
        val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        lp.bottomMargin = dp(12)
        c.layoutParams = lp
        return c
    }

    private fun advice(t: String): TextView = txt(t, 13, 0xFF8A8A92.toInt(), 0).apply {
        setPadding(dp(10), 0, 0, 0)
    }

    private fun toast(t: String) {
        android.widget.Toast.makeText(this, t, android.widget.Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        RestService.onTick = null
        RestService.onDone = null
        MusicService.onChange = null
    }
}
