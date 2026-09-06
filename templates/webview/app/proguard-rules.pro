# Fuer den WebView-Wrapper wird standardmaessig nicht minifiziert.
# Falls JavaScript per @JavascriptInterface auf Java zugreift, muessen die
# betroffenen Methoden hier behalten werden:
# -keepclassmembers class * {
#     @android.webkit.JavascriptInterface <methods>;
# }
