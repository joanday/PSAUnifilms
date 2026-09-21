package com.example.my_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blocks screenshots and screen recording of this app, and also
        // hides its content in the Recent Apps / task switcher preview.
        // Must be set here in native Android code -- there is no Dart-side
        // equivalent, so this is lost if MainActivity.kt is ever
        // regenerated or reset (e.g. `flutter create .` re-run).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}