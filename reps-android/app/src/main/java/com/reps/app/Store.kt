package com.reps.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 数据层：动作库 / 训练记录 / 当前会话，存 SharedPreferences(JSON)。
 * 结构对齐网页版，方便以后做导入导出。
 */
object Store {

    private const val PREF = "reps_store"
    private const val KEY = "db"

    data class SetRec(val w: Double, val r: Int, val ts: Long)

    class Ex(val name: String, val sets: MutableList<SetRec> = mutableListOf())

    class Session(val date: Long, val exercises: MutableList<Ex> = mutableListOf())

    val lib = mutableListOf<Pair<String, String>>()   // 部位 to 名称
    val sessions = mutableListOf<Session>()

    var cur: Session? = null
    var curIdx = 0
    var w = 10.0
    var r = 10
    var restSec = 120
    var trackName: String = ""
    var trackUri: String = ""

    private var sp: android.content.SharedPreferences? = null

    private val DEFAULT = listOf(
        "胸" to "卧推", "胸" to "上斜卧推", "胸" to "哑铃飞鸟", "胸" to "双杠臂屈伸",
        "背" to "引体向上", "背" to "高位下拉", "背" to "杠铃划船", "背" to "坐姿划船", "背" to "直臂下压",
        "腿" to "深蹲", "腿" to "硬拉", "腿" to "腿举", "腿" to "保加利亚分腿蹲", "腿" to "腿弯举",
        "肩" to "实力推", "肩" to "侧平举", "肩" to "后束绳索Y举", "肩" to "面拉", "肩" to "绳索Y字举",
        "臂" to "杠铃弯举", "臂" to "锤式弯举", "臂" to "绳索下压", "臂" to "窄距卧推",
        "核心" to "悬垂举腿", "核心" to "卷腹", "核心" to "反向山羊挺身"
    )

    fun init(c: Context) {
        sp = c.applicationContext.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val s = sp?.getString(KEY, null)
        if (s.isNullOrBlank()) { resetLib(); return }
        try {
            val o = JSONObject(s)
            lib.clear()
            o.optJSONArray("lib")?.let { a ->
                for (i in 0 until a.length()) {
                    val x = a.getJSONObject(i)
                    lib.add(x.getString("g") to x.getString("n"))
                }
            }
            sessions.clear()
            o.optJSONArray("sessions")?.let { a ->
                for (i in 0 until a.length()) sessions.add(readSession(a.getJSONObject(i)))
            }
            w = o.optDouble("w", 10.0)
            r = o.optInt("r", 10)
            restSec = o.optInt("restSec", 120)
            trackName = o.optString("trackName", "")
            trackUri = o.optString("trackUri", "")
            curIdx = o.optInt("curIdx", 0)
            val curJson = o.optJSONObject("cur")
            cur = if (curJson == null) null else readSession(curJson)
            if (lib.isEmpty()) resetLib()
        } catch (e: Exception) {
            resetLib()
        }
    }

    private fun resetLib() {
        lib.clear()
        lib.addAll(DEFAULT)
        save()
    }

    fun save() {
        try {
            val o = JSONObject()
            val la = JSONArray()
            lib.forEach { la.put(JSONObject().put("g", it.first).put("n", it.second)) }
            o.put("lib", la)
            val sa = JSONArray()
            sessions.forEach { sa.put(writeSession(it)) }
            o.put("sessions", sa)
            o.put("w", w)
            o.put("r", r)
            o.put("restSec", restSec)
            o.put("trackName", trackName)
            o.put("trackUri", trackUri)
            o.put("curIdx", curIdx)
            cur?.let { o.put("cur", writeSession(it)) }
            sp?.edit()?.putString(KEY, o.toString())?.apply()
        } catch (e: Exception) {
        }
    }

    private fun writeSession(s: Session): JSONObject {
        val o = JSONObject().put("date", s.date)
        val ea = JSONArray()
        s.exercises.forEach { e ->
            val eo = JSONObject().put("name", e.name)
            val sta = JSONArray()
            e.sets.forEach { st -> sta.put(JSONObject().put("w", st.w).put("r", st.r).put("ts", st.ts)) }
            eo.put("sets", sta)
            ea.put(eo)
        }
        o.put("ex", ea)
        return o
    }

    private fun readSession(o: JSONObject): Session {
        val s = Session(o.optLong("date", System.currentTimeMillis()))
        o.optJSONArray("ex")?.let { a ->
            for (i in 0 until a.length()) {
                val eo = a.getJSONObject(i)
                val e = Ex(eo.getString("name"))
                eo.optJSONArray("sets")?.let { sa ->
                    for (j in 0 until sa.length()) {
                        val so = sa.getJSONObject(j)
                        e.sets.add(SetRec(so.optDouble("w", 0.0), so.optInt("r", 0), so.optLong("ts", 0)))
                    }
                }
                s.exercises.add(e)
            }
        }
        return s
    }

    // ---------- 会话 ----------
    fun ensureSession(): Session {
        cur?.let { if (it.exercises.isNotEmpty()) return it }
        val s = Session(System.currentTimeMillis())
        s.exercises.add(Ex(lib.firstOrNull()?.second ?: "卧推"))
        cur = s
        curIdx = 0
        save()
        return s
    }

    fun currentEx(): Ex {
        val s = ensureSession()
        if (curIdx >= s.exercises.size) curIdx = s.exercises.size - 1
        if (curIdx < 0) curIdx = 0
        return s.exercises[curIdx]
    }

    fun finishSession(): Boolean {
        val s = cur ?: return false
        val real = s.exercises.filter { it.sets.isNotEmpty() }
        if (real.isEmpty()) return false
        sessions.add(Session(s.date, real.toMutableList()))
        cur = null
        curIdx = 0
        save()
        return true
    }

    /** 某动作的历史（已完成 + 当前未结束的那次） */
    fun historyOf(name: String): List<Pair<Long, List<SetRec>>> {
        val out = mutableListOf<Pair<Long, List<SetRec>>>()
        sessions.forEach { s ->
            s.exercises.firstOrNull { it.name == name && it.sets.isNotEmpty() }?.let { out.add(s.date to it.sets) }
        }
        cur?.let { s ->
            s.exercises.firstOrNull { it.name == name && it.sets.isNotEmpty() }?.let { out.add(s.date to it.sets) }
        }
        return out
    }

    fun e1rm(w: Double, r: Int): Double = if (r > 0) w * (1 + r / 30.0) else 0.0

    fun weekCapacity(): Int {
        val weekAgo = System.currentTimeMillis() - 7L * 86400000L
        var sum = 0.0
        sessions.forEach { s ->
            if (s.date < weekAgo) return@forEach
            s.exercises.forEach { e -> e.sets.forEach { sum += it.w * it.r } }
        }
        return Math.round(sum).toInt()
    }
}
