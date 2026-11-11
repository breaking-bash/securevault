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