package com.reps.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** 动作库：从 assets/moves.json 读 109 个动作（要领/常见错误/替代） */
object MoveLib {

    data class Move(
        val n: String,
        val en: String,
        val g: String,
        val eq: String,
        val p: String,
        val mus: String,
        val cue: List<String>,
        val err: List<String>,
        val alt: List<String>
    )

    val all = mutableListOf<Move>()

    fun load(c: Context) {
        if (all.isNotEmpty()) return
        try {
            val txt = c.assets.open("moves.json").bufferedReader().use { it.readText() }
            val arr = JSONObject(txt).getJSONArray("moves")
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                all.add(
                    Move(
                        o.getString("n"),
                        o.optString("en", ""),
                        o.optString("g", "其他"),
                        o.optString("eq", ""),
                        o.optString("p", ""),
                        o.optString("mus", ""),
                        strList(o.optJSONArray("cue")),
                        strList(o.optJSONArray("err")),
                        strList(o.optJSONArray("alt"))
                    )
                )
            }
        } catch (e: Exception) {
        }
    }

    private fun strList(a: JSONArray?): List<String> {
        if (a == null) return emptyList()
        val out = mutableListOf<String>()
        for (i in 0 until a.length()) out.add(a.optString(i))
        return out
    }

    fun find(n: String): Move? = all.firstOrNull { it.n == n }

    fun search(q: String): List<Move> {
        if (q.isBlank()) return emptyList()
        val k = q.trim().lowercase()
        return all.filter {
            (it.n + it.en + it.mus + it.eq + it.g + it.p).lowercase().contains(k)
        }
    }
}
