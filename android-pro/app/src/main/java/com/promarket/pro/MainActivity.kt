package com.promarket.pro

import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.launch

/**
 * Live feed (screen 2 in the PRD). Onboarding (OTP, categories, documents),
 * map view, job lifecycle and wallet screens are the next milestones.
 */
class MainActivity : AppCompatActivity() {
    private val api = ApiClient()
    private lateinit var list: LinearLayout
    // TODO: replace with the id returned from OTP onboarding.
    private val proId = "DEMO_PRO_ID"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        api.userId = proId
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 32, 32, 32) }
        val toggle = MaterialSwitch(this).apply {
            text = getString(R.string.available)
            setOnCheckedChangeListener { _, on -> lifecycleScope.launch { runCatching { api.setAvailable(proId, on) } ; refresh() } }
        }
        list.addView(toggle)
        setContentView(ScrollView(this).apply { addView(list, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT) })
        refresh()
    }

    private fun refresh() = lifecycleScope.launch {
        while (list.childCount > 1) list.removeViewAt(1)
        val jobs = runCatching { api.feed(proId) }.getOrElse { toast(it.message); return@launch }
        for (i in 0 until jobs.length()) {
            val job = jobs.getJSONObject(i)
            list.addView(TextView(this@MainActivity).apply {
                text = "${job.getString("description")}\n${job.optDouble("distanceKm")} ק\"מ · ₪${job.getInt("leadPrice")} · נותרו ${job.getInt("claimsLeft")}"
                textSize = 16f
            })
            list.addView(Button(this@MainActivity).apply {
                text = getString(R.string.claim)
                setOnClickListener { claim(job.getString("id")) }
            })
        }
    }

    private fun claim(jobId: String) = lifecycleScope.launch {
        runCatching { api.claim(jobId) }
            .onSuccess { j ->
                toast("טלפון: ${j.getString("phone")}")
                val loc = j.getJSONObject("location")
                navigateTo(loc.getDouble("lat"), loc.getDouble("lng"))
            }
            .onFailure { toast(it.message) }
        refresh()
    }

    private fun toast(msg: String?) = Toast.makeText(this, msg ?: "שגיאה", Toast.LENGTH_LONG).show()
}
