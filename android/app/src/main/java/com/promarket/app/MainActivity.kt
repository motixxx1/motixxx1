package com.promarket.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import android.webkit.GeolocationPermissions
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

/**
 * App shell around the web app (client "/" or pro "/pro", chosen by build flavor).
 * Adds what the browser can't: location permission, phone dialer, Waze, photo picker,
 * back navigation and pull-to-refresh. Native screens can replace pages one by one.
 *
 * Location: browsers only allow geolocation on https, and the server may run on plain
 * http on the local network, so the app reads the location itself and exposes it to the
 * page as window.ProMarketApp.location().
 */
class MainActivity : AppCompatActivity() {
    private lateinit var web: WebView
    private lateinit var refresh: SwipeRefreshLayout
    private var pendingGeo: Pair<String, GeolocationPermissions.Callback>? = null
    private var pendingFiles: ValueCallback<Array<Uri>>? = null
    @Volatile private var lastLocation: Location? = null
    private val locationManager by lazy { getSystemService(LOCATION_SERVICE) as LocationManager }

    // All four methods overridden: before Android 11 they have no default implementations.
    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) { lastLocation = location }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    /** Called from JavaScript: returns {"lat":..,"lng":..} or "" when unknown. */
    inner class Bridge {
        @JavascriptInterface
        fun location(): String {
            val l = lastLocation ?: return ""
            return "{\"lat\":${l.latitude},\"lng\":${l.longitude}}"
        }
    }

    private val prefs by lazy { getSharedPreferences("settings", MODE_PRIVATE) }
    // Built-in addresses, comma separated, public first then LAN (BuildConfig.SERVER_URL).
    private val defaults: List<String>
        get() = BuildConfig.SERVER_URL.split(',').map { it.trim().trimEnd('/') }.filter { it.isNotEmpty() }
    // The address that worked last, or one typed by the user; null until the first connection.
    private var serverUrl: String = ""
    private var autoRetried = false

    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingGeo?.let { (origin, cb) -> cb.invoke(origin, granted, false) }
        pendingGeo = null
        if (granted) startLocationUpdates()
    }
    // File chooser for <input type="file">: honors accept (photos / video) and multiple selection.
    private val pickFiles = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        pendingFiles?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data))
        pendingFiles = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        refresh = SwipeRefreshLayout(this).apply {
            addView(web)
            setOnRefreshListener { web.reload() }
        }
        setContentView(refresh)

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true // the login token lives in localStorage
            setGeolocationEnabled(true)
        }
        web.addJavascriptInterface(Bridge(), "ProMarketApp")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                if (url.scheme in listOf("http", "https") && (url.host == Uri.parse(serverUrl).host || defaults.any { url.host == Uri.parse(it).host })) return false
                openExternal(url) // tel:, Waze links, anything outside our server
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                refresh.isRefreshing = false
                autoRetried = false
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) {
                    refresh.isRefreshing = false
                    // Maybe the network changed (Wi-Fi <-> mobile): re-pick the address, but only once in a row.
                    if (autoRetried) askServer(getString(R.string.server_unreachable)) else { autoRetried = true; connect() }
                }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                if (hasLocationPermission()) {
                    callback.invoke(origin, true, false)
                } else {
                    pendingGeo = origin to callback
                    locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                }
            }

            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                pendingFiles?.onReceiveValue(null)
                pendingFiles = callback
                return try {
                    pickFiles.launch(params.createIntent())
                    true
                } catch (e: ActivityNotFoundException) {
                    pendingFiles = null
                    false
                }
            }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else finish()
            }
        })

        if (hasLocationPermission()) startLocationUpdates()
        else locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)

        when {
            savedInstanceState != null -> web.restoreState(savedInstanceState)
            else -> connect()
        }
    }

    private fun load() = web.loadUrl(serverUrl + BuildConfig.START_PATH)

    /** Picks the first reachable address (typed one, then public, then LAN) without asking the user. */
    private fun connect() {
        refresh.isRefreshing = true
        val candidates = (listOfNotNull(prefs.getString("server_url", null)) + defaults).map { it.trimEnd('/') }.distinct()
        Thread {
            val found = candidates.firstOrNull { reachable(it) }
            runOnUiThread {
                if (isFinishing) return@runOnUiThread
                if (found != null) {
                    serverUrl = found
                    load()
                } else {
                    refresh.isRefreshing = false
                    serverUrl = candidates.firstOrNull().orEmpty()
                    askServer(getString(if (candidates.isEmpty()) R.string.server_first_time else R.string.server_unreachable))
                }
            }
        }.start()
    }

    private fun reachable(base: String): Boolean = try {
        val c = java.net.URL("$base/healthz").openConnection() as java.net.HttpURLConnection
        c.connectTimeout = 3000
        c.readTimeout = 3000
        c.responseCode in 200..399
    } catch (e: Exception) {
        false
    }

    private fun hasLocationPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        if (!hasLocationPermission()) return
        for (provider in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
            if (!locationManager.isProviderEnabled(provider)) continue
            if (lastLocation == null) lastLocation = locationManager.getLastKnownLocation(provider)
            locationManager.requestLocationUpdates(provider, 30_000L, 25f, locationListener, Looper.getMainLooper())
        }
    }

    override fun onDestroy() {
        locationManager.removeUpdates(locationListener)
        super.onDestroy()
    }

    private fun openExternal(uri: Uri) {
        val intent = if (uri.scheme == "tel") Intent(Intent.ACTION_DIAL, uri) else Intent(Intent.ACTION_VIEW, uri)
        try {
            startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            // No app can open this link; ignore.
        }
    }

    /** First launch, or the server can't be reached: let the user set or retry the address. */
    private fun askServer(message: String) {
        if (isFinishing) return
        val input = EditText(this).apply {
            setText(serverUrl.ifBlank { "https://" })
            setSingleLine()
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.server_title)
            .setMessage(message)
            .setView(input)
            .setCancelable(false)
            .setPositiveButton(R.string.connect) { _, _ ->
                prefs.edit().putString("server_url", input.text.toString().trim().trimEnd('/')).apply()
                connect()
            }
            .setNeutralButton(R.string.retry) { _, _ -> connect() }
            .show()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }
}
