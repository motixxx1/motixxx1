package com.promarket.pro

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Thin client for the backend REST API (see backend/src/app.js). */
class ApiClient(private val base: String = BuildConfig.API_BASE, var userId: String? = null) {

    suspend fun feed(proId: String): JSONArray = JSONArray(request("GET", "/api/pros/$proId/feed"))
    suspend fun claim(jobId: String): JSONObject = JSONObject(request("POST", "/api/jobs/$jobId/claim", JSONObject()))
    suspend fun setAvailable(proId: String, available: Boolean) =
        request("PUT", "/api/pros/$proId/availability", JSONObject().put("available", available))
    suspend fun updateLocation(proId: String, lat: Double, lng: Double) =
        request("PUT", "/api/pros/$proId/location", JSONObject().put("lat", lat).put("lng", lng))

    private suspend fun request(method: String, path: String, body: JSONObject? = null): String =
        withContext(Dispatchers.IO) {
            val conn = URL(base + path).openConnection() as HttpURLConnection
            conn.requestMethod = method
            conn.setRequestProperty("content-type", "application/json")
            userId?.let { conn.setRequestProperty("x-user-id", it) }
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

class ApiException(val status: Int, body: String) : Exception("HTTP $status: $body")
