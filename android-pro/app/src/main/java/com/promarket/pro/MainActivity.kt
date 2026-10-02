package com.promarket.pro

import android.os.Bundle
import android.text.InputType
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.materialswitch.MaterialSwitch
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Live feed (screen 2 in the PRD): open requests the pro can answer with an offer.
 * Onboarding (OTP, categories, documents), map view, active-job screens and
 * wallet are the next milestones.
 */
class MainActivity : AppCompatActivity() {
    private val api = ApiClient()
    private lateinit var list: LinearLayout
    // TODO: replace with the id returned from OTP onboarding.
    private val proId = "DEMO_PRO_ID"
    private val modeLabel = mapOf("onsite" to "🏠 אצל הלקוח", "remote" to "💻 מרחוק", "phone" to "📞 בטלפון")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        api.userId = proId
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 32, 32, 32) }
        val toggle = MaterialSwitch(this).apply {
            text = getString(R.string.available)
            setOnCheckedChangeListener { _, on -> lifecycleScope.launch { runCatching { api.setAvailable(proId, on) }; refresh() } }
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
            val distance = if (job.has("distanceKm")) " · ${job.getDouble("distanceKm")} ק\"מ" else ""
            list.addView(TextView(this@MainActivity).apply {
                text = "${job.getString("description")}\n${modeLabel[job.getString("mode")]}$distance · " +
                    "עלות הצעה ₪${job.getInt("leadPrice")} · נותרו ${job.getInt("offersLeft")}"
                textSize = 16f
            })
            list.addView(Button(this@MainActivity).apply {
                text = getString(R.string.send_offer)
                setOnClickListener { offerDialog(job.getString("id")) }
            })
        }
    }

    private fun offerDialog(jobId: String) {
        val price = EditText(this).apply { hint = "מחיר ₪ (ריק = אחרי בדיקה)"; inputType = InputType.TYPE_CLASS_NUMBER }
        val message = EditText(this).apply { hint = "הודעה ללקוח" }
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(48, 16, 48, 0); addView(price); addView(message) }
        AlertDialog.Builder(this)
            .setTitle(R.string.send_offer)
            .setView(form)
            .setPositiveButton(R.string.send) { _, _ ->
                sendOffer(jobId, price.text.toString().toIntOrNull(), message.text.toString())
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun sendOffer(jobId: String, price: Int?, message: String) = lifecycleScope.launch {
        runCatching { api.sendOffer(jobId, price, message) }
            .onSuccess { job -> if (job.has("phone")) contactDialog(job) else toast("ההצעה נשלחה ללקוח") }
            .onFailure { toast(it.message) }
        refresh()
    }

    /** Shown when the client allowed calls: call now, and navigate for onsite jobs. */
    private fun contactDialog(job: JSONObject) {
        val phone = job.getString("phone")
        val b = AlertDialog.Builder(this)
            .setTitle("הלקוח אישר שיחה")
            .setMessage(phone)
            .setPositiveButton(R.string.call) { _, _ -> dial(phone) }
        if (job.getString("mode") == "onsite" && job.has("location")) {
            val loc = job.getJSONObject("location")
            b.setNeutralButton(R.string.navigate) { _, _ -> navigateTo(loc.getDouble("lat"), loc.getDouble("lng")) }
        }
        b.show()
    }

    private fun toast(msg: String?) = Toast.makeText(this, msg ?: "שגיאה", Toast.LENGTH_LONG).show()
}
