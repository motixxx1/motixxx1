package com.promarket.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.webkit.GeolocationPermissions
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
 */
class MainActivity : AppCompatActivity() {
    private lateinit var web: WebView
    private lateinit var refresh: SwipeRefreshLayout
    private var pendingGeo: Pair<String, GeolocationPermissions.Callback>? = null
    private var pendingFiles: ValueCallback<Array<Uri>>? = null

    private val prefs by lazy { getSharedPreferences("settings", MODE_PRIVATE) }
    private val serverUrl: String
        get() = (prefs.getString("server_url", null) ?: BuildConfig.SERVER_URL).trimEnd('/')

    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingGeo?.let { (origin, cb) -> cb.invoke(origin, granted, false) }
        pendingGeo = null
    }
    private val pickImages = registerForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        pendingFiles?.onReceiveValue(uris.toTypedArray())
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
                    askServer(getString(R.string.server_unreachable))
                }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
                val granted = ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
                if (granted) {
                    callback.invoke(origin, true, false)
                } else {
                    pendingGeo = origin to callback
                    locationPermission.launch(Manifest.permission.ACCESS_FINE_LOCATION)
                }
            }

            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                pendingFiles?.onReceiveValue(null)
                pendingFiles = callback
                pickImages.launch("image/*")
                return true
            }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else finish()
            }
        })

        when {
            savedInstanceState != null -> web.restoreState(savedInstanceState)
            serverUrl.isBlank() -> askServer(getString(R.string.server_first_time))
            else -> load()
        }
    }

    private fun load() = web.loadUrl(serverUrl + BuildConfig.START_PATH)

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
