package com.promarket.pro

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/** Opens Waze, falling back to any maps app (Google Maps) via geo: URI. */
fun Context.navigateTo(lat: Double, lng: Double) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("waze://?ll=$lat,$lng&navigate=yes")))
    } catch (e: ActivityNotFoundException) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("geo:$lat,$lng?q=$lat,$lng")))
    }
}

/** Opens the dialer with the number filled in (no CALL_PHONE permission needed). */
fun Context.dial(phone: String) {
    startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
}
