package com.promarket.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.ViewGroup
import android.view.WindowManager
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
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

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

    /** Called from JavaScript as window.ProMarketApp.*. */
    inner class Bridge {
        /** {"lat":..,"lng":..} or "" when unknown. */
        @JavascriptInterface
        fun location(): String {
            val l = lastLocation ?: return ""
            return "{\"lat\":${l.latitude},\"lng\":${l.longitude}}"
        }

        /** A new request popped up: buzz like a courier app. */
        @JavascriptInterface
        fun vibrate(ms: Int) {
            val v = if (Build.VERSION.SDK_INT >= 31) (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            else @Suppress("DEPRECATION") (getSystemService(VIBRATOR_SERVICE) as Vibrator)
            v.vibrate(VibrationEffect.createOneShot(ms.coerceIn(1, 2000).toLong(), VibrationEffect.DEFAULT_AMPLITUDE))
        }

        /** Keep the screen on while a pro is available for requests. */
        @JavascriptInterface
        fun keepScreenOn(on: Boolean) = runOnUiThread {
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }

        /** Payment pages and other https links open in the phone's browser. */
        @JavascriptInterface
        fun openExternal(url: String) = runOnUiThread {
            if (url.startsWith("https://")) runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }

        @JavascriptInterface
        fun appVersion(): Int = BuildConfig.VERSION_CODE
    }

    private val prefs by lazy { getSharedPreferences("settings", MODE_PRIVATE) }
    private val serverUrl: String
        get() = (prefs.getString("server_url", null) ?: BuildConfig.SERVER_URL).trimEnd('/')

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
        // Edge to edge (enforced from API 35): the page color shows behind the status and
        // navigation bars, and the page is padded so nothing hides under them or the keyboard.
        val dark = BuildConfig.FLAVOR == "pro"
        val bars = if (dark) SystemBarStyle.dark(Color.TRANSPARENT) else SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        enableEdgeToEdge(statusBarStyle = bars, navigationBarStyle = bars)
        val bg = ContextCompat.getColor(this, R.color.bg)
        web = WebView(this).apply { setBackgroundColor(bg) }
        refresh = SwipeRefreshLayout(this).apply {
            // MATCH_PARENT: with the default WRAP_CONTENT the page's viewport height (vh) is wrong,
            // which squeezed bottom sheets (e.g. the offer screen) to a thin strip.
            addView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            setBackgroundColor(bg)
            setOnRefreshListener { web.reload() }
        }
        ViewCompat.setOnApplyWindowInsetsListener(refresh) { v, insets ->
            val i = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.ime())
            v.setPadding(i.left, i.top, i.right, i.bottom)
            WindowInsetsCompat.CONSUMED
        }
        setContentView(refresh)

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true // the login token lives in localStorage
            setGeolocationEnabled(true)
            mediaPlaybackRequiresUserGesture = false // the new-request sound
        }
        web.addJavascriptInterface(Bridge(), "ProMarketApp")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                if (url.scheme in listOf("http", "https") && url.host == Uri.parse(serverUrl).host) return false
                openExternal(url) // tel:, Waze links, anything outside our server
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                refresh.isRefreshing = false
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) {
                    refresh.isRefreshing = false
                    if (BuildConfig.SIDELOAD) askServer(getString(R.string.server_unreachable)) else showOffline()
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
            serverUrl.isBlank() -> askServer(getString(R.string.server_first_time))
            else -> load()
        }
        checkForUpdate()
    }

    /** Store build: the server is fixed, so just offer to retry. */
    private fun showOffline() {
        if (isFinishing) return
        AlertDialog.Builder(this)
            .setTitle(R.string.offline_title)
            .setMessage(R.string.offline_message)
            .setCancelable(false)
            .setPositiveButton(R.string.retry) { _, _ -> load() }
            .show()
    }

    /**
     * Sideloaded APK only (the store build updates through Google Play): screens and features come
     * from the server, so a new APK is offered only when the native shell itself changed.
     */
    private fun checkForUpdate() {
        if (!BuildConfig.SIDELOAD || serverUrl.isBlank()) return
        val base = serverUrl
        Thread {
            try {
                val c = URL("$base/api/version").openConnection() as HttpURLConnection
                c.connectTimeout = 5000
                c.readTimeout = 5000
                val latest = JSONObject(c.inputStream.bufferedReader().use { it.readText() }).optInt("apk", 0)
                c.disconnect()
                if (latest > BuildConfig.VERSION_CODE && prefs.getInt("update_dismissed", 0) < latest) runOnUiThread { offerUpdate(latest) }
            } catch (e: Exception) {
                // Offline or an old server: try again next launch.
            }
        }.start()
    }

    private fun offerUpdate(latest: Int) {
        if (isFinishing) return
        val apk = "https://github.com/motixxx1/motixxx1/releases/download/promarket-latest/ProMarket-${BuildConfig.FLAVOR}.apk"
        AlertDialog.Builder(this)
            .setTitle(R.string.update_title)
            .setMessage(R.string.update_message)
            .setPositiveButton(R.string.update_download) { _, _ -> openExternal(Uri.parse(apk)) }
            .setNegativeButton(R.string.update_later) { _, _ -> prefs.edit().putInt("update_dismissed", latest).apply() }
            .show()
    }

    private fun load() = web.loadUrl(serverUrl + BuildConfig.START_PATH)

    private fun hasLocationPermission() =
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        if (!hasLocationPermission()) return
        for (provider in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
            if (!locationManager.isProviderEnabled(provider)) continue
            if (lastLocation == null) lastLocation = locationManager.getLastKnownLocation(provider)
            // Pros share their position every few seconds so the customer sees them move; customers need it once.
            val pro = BuildConfig.FLAVOR == "pro"
            locationManager.requestLocationUpdates(provider, if (pro) 4_000L else 30_000L, if (pro) 5f else 25f, locationListener, Looper.getMainLooper())
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
                load()
            }
            .setNeutralButton(R.string.retry) { _, _ -> load() }
            .show()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }
}
