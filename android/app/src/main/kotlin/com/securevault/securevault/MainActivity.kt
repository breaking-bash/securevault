package com.securevault.securevault

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth so the biometric prompt
// can be hosted in a FragmentActivity (needed for BiometricPrompt).
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Blocks screenshots, screen recording and the recents thumbnail.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securevault/autofill")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRequest" -> result.success(null)
                    "isEnabled" -> {
                        val m = getSystemService(AutofillManager::class.java)
                        result.success(m?.hasEnabledAutofillServices() == true)
                    }
                    "setSecure" -> {
                        val on = call.arguments as? Boolean ?: true
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "setAutofillPrefs" -> {
                        getSharedPreferences("sv_prefs", MODE_PRIVATE).edit()
                            .putBoolean("inline", call.argument<Boolean>("inline") ?: true)
                            .putBoolean("save", call.argument<Boolean>("save") ?: true)
                            .apply()
                        result.success(null)
                    }
                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                                .setData(Uri.parse("package:$packageName"))
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}