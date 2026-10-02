package com.promarket.pro

import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** One-screen signup/login: name + phone -> SMS code. New pros get welcome credit. */
class LoginActivity : AppCompatActivity() {
    private val api = ApiClient()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val name = EditText(this).apply { hint = "שם מלא" }
        val phone = EditText(this).apply { hint = "טלפון נייד"; inputType = InputType.TYPE_CLASS_PHONE }
        val referral = EditText(this).apply { hint = "קוד חבר (לא חובה)" }
        val code = EditText(this).apply { hint = "קוד מה-SMS"; inputType = InputType.TYPE_CLASS_NUMBER; isEnabled = false }
        val button = Button(this).apply { text = "שלחו לי קוד" }
        button.setOnClickListener {
            lifecycleScope.launch {
                runCatching {
                    if (!code.isEnabled) {
                        val res = api.requestCode(phone.text.toString())
                        code.isEnabled = true
                        res.optString("devCode").takeIf { it.isNotBlank() }?.let { code.setText(it) } // dev server only
                        button.text = "כניסה"
                    } else {
                        val res = api.verify(phone.text.toString(), code.text.toString(), name.text.toString(),
                            referral.text.toString().ifBlank { null })
                        Session.save(this@LoginActivity, res.getString("token"))
                        startActivity(Intent(this@LoginActivity, MainActivity::class.java))
                        finish()
                    }
                }.onFailure { Toast.makeText(this@LoginActivity, it.message, Toast.LENGTH_LONG).show() }
            }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
            addView(TextView(this@LoginActivity).apply { text = "נרשמים בדקה ומתחילים להרוויח"; textSize = 22f })
            addView(TextView(this@LoginActivity).apply { text = "30 ₪ קרדיט מתנה לשליחת הצעות ראשונות" })
            listOf(name, phone, referral, code, button).forEach(::addView)
        })
    }
}
