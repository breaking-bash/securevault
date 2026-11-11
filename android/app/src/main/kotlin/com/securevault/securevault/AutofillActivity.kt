package com.securevault.securevault

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hosts the Flutter UI (unlock + pick a login) for an autofill request. */
class AutofillActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    companion object {
        const val EXTRA_DOMAIN = "sv_domain"
        const val EXTRA_PACKAGE = "sv_package"
        const val EXTRA_USER_ID = "sv_user_id"
        const val EXTRA_PASS_ID = "sv_pass_id"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securevault/autofill")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRequest" -> result.success(
                        mapOf(
                            "domain" to intent.getStringExtra(EXTRA_DOMAIN),
                            "package" to intent.getStringExtra(EXTRA_PACKAGE)
                        )
                    )
                    "fill" -> {
                        fill(
                            call.argument<String>("username") ?: "",
                            call.argument<String>("password") ?: ""
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        setResult(Activity.RESULT_CANCELED)
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun fill(username: String, password: String) {
        val userId = intent.getParcelableExtra<AutofillId>(EXTRA_USER_ID)
        val passId = intent.getParcelableExtra<AutofillId>(EXTRA_PASS_ID)
        val pres = RemoteViews(packageName, R.layout.autofill_item)
        val ds = Dataset.Builder(pres)
        userId?.let { ds.setValue(it, AutofillValue.forText(username)) }
        passId?.let { ds.setValue(it, AutofillValue.forText(password)) }
        setResult(
            Activity.RESULT_OK,
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, ds.build())
        )
        finish()
    }
}
