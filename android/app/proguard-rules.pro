# The page calls these through window.ProMarketApp, so R8 must not rename or remove them.
-keepclassmembers class com.promarket.app.MainActivity$Bridge {
    @android.webkit.JavascriptInterface <methods>;
}
