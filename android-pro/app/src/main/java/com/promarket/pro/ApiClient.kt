package com.promarket.pro

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Thin client for the backend REST API (see backend/src/app.js). */
class ApiClient(private val base: String = BuildConfig.API_BASE, var token: String? = null) {

    // ---- Login: phone -> SMS code -> token (account is created on first login)
    suspend fun requestCode(phone: String): JSONObject =
        JSONObject(request("POST", "/api/auth/request", JSONObject().put("phone", phone)))
    suspend fun verify(phone: String, code: String, name: String, referralCode: String?): JSONObject = JSONObject(
        request("POST", "/api/auth/verify", JSONObject().put("phone", phone).put("code", code)
            .put("role", "pro").put("name", name).put("referralCode", referralCode ?: JSONObject.NULL))
    )

    suspend fun me(): JSONObject = JSONObject(request("GET", "/api/pro/me"))
    suspend fun feed(): JSONArray = JSONArray(request("GET", "/api/pro/feed"))
    suspend fun myJobs(): JSONArray = JSONArray(request("GET", "/api/pro/jobs"))
    suspend fun setAvailable(available: Boolean) =
        request("PUT", "/api/pro/availability", JSONObject().put("available", available))
    suspend fun updateLocation(lat: Double, lng: Double) =
        request("PUT", "/api/pro/location", JSONObject().put("lat", lat).put("lng", lng))
    suspend fun sendOffer(jobId: String, price: Int?, message: String): JSONObject = JSONObject(
        request("POST", "/api/jobs/$jobId/offers", JSONObject().put("price", price ?: JSONObject.NULL).put("message", message))
    )
    suspend fun addLog(jobId: String, text: String) =
        request("POST", "/api/jobs/$jobId/log", JSONObject().put("text", text))
    suspend fun setStatus(jobId: String, status: String) =
        request("POST", "/api/jobs/$jobId/status", JSONObject().put("status", status))

    private suspend fun request(method: String, path: String, body: JSONObject? = null): String =
        withContext(Dispatchers.IO) {
            val conn = URL(base + path).openConnection() as HttpURLConnection
            conn.requestMethod = method
            conn.setRequestProperty("content-type", "application/json")
            token?.let { conn.setRequestProperty("authorization", "Bearer $it") }
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
            }
            val ok = conn.responseCode in 200..299
            val text = (if (ok) conn.inputStream else conn.errorStream).bufferedReader().use { it.readText() }
            if (!ok) throw ApiException(conn.responseCode, text)
            text
        }
}

class ApiException(val status: Int, body: String) : Exception(
    runCatching { JSONObject(body).optString("message") }.getOrNull()?.ifBlank { null } ?: "HTTP $status"
)

/** Persists the login token. TODO: move to EncryptedSharedPreferences. */
object Session {
    private const val PREFS = "session"
    fun token(ctx: Context): String? = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("token", null)
    fun save(ctx: Context, token: String?) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("token", token).apply()
}
