package com.securevault.securevault

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import android.graphics.drawable.Icon
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi

/**
 * Detects username/password fields and offers a single "Autofill with
 * SecureVault" suggestion. Tapping it opens [AutofillActivity], where the user
 * unlocks the vault and picks a login. No secrets are handled in this service.
 */
class SecureVaultAutofillService : AutofillService() {

    private class Fields {
        var userId: AutofillId? = null
        var passId: AutofillId? = null
        var lastText: AutofillId? = null
        var domain: String? = null
        val values = HashMap<AutofillId, String>()
    }

    private fun prefs() = getSharedPreferences("sv_prefs", MODE_PRIVATE)

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val structure = request.fillContexts.last().structure
        val pkg = structure.activityComponent?.packageName
        if (pkg == packageName) {
            callback.onSuccess(null)
            return
        }
        val f = Fields()
        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode, f)
        }
        if (f.passId == null && f.userId == null) {
            callback.onSuccess(null)
            return
        }

        val intent = Intent(this, AutofillActivity::class.java)
            .putExtra(AutofillActivity.EXTRA_DOMAIN, f.domain)
            .putExtra(AutofillActivity.EXTRA_PACKAGE, pkg)
            .putExtra(AutofillActivity.EXTRA_USER_ID, f.userId)
            .putExtra(AutofillActivity.EXTRA_PASS_ID, f.passId)
        var flags = PendingIntent.FLAG_CANCEL_CURRENT
        if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
        val sender = PendingIntent.getActivity(
            this, (System.nanoTime() and 0x7fffffff).toInt(), intent, flags
        ).intentSender

        val presentation = RemoteViews(packageName, R.layout.autofill_item)
        presentation.setTextViewText(
            R.id.autofill_label,
            "SecureVault" + (f.domain?.let { " · $it" } ?: "")
        )
        val ds = Dataset.Builder(presentation)
        f.userId?.let { ds.setValue(it, null) }
        f.passId?.let { ds.setValue(it, null) }
        if (Build.VERSION.SDK_INT >= 30 && prefs().getBoolean("inline", true)) {
            inlinePresentation(request, "SecureVault" + (f.domain?.let { " · $it" } ?: ""))
                ?.let { ds.setInlinePresentation(it) }
        }
        ds.setAuthentication(sender)
        val response = FillResponse.Builder().addDataset(ds.build())
        val passId = f.passId
        if (passId != null && prefs().getBoolean("save", true)) {
            val save = SaveInfo.Builder(
                SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                arrayOf(passId)
            )
            f.userId?.let { save.setOptionalIds(arrayOf(it)) }
            save.setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
            response.setSaveInfo(save.build())
        }
        callback.onSuccess(response.build())
    }

    @androidx.annotation.RequiresApi(30)
    private fun inlinePresentation(request: FillRequest, title: String): InlinePresentation? {
        val spec = request.inlineSuggestionsRequest?.inlinePresentationSpecs?.firstOrNull()
            ?: return null
        if (!UiVersions.getVersions(spec.style).contains(UiVersions.INLINE_UI_VERSION_1)) return null
        val attribution = PendingIntent.getService(
            this, 0, Intent(), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val content = InlineSuggestionUi.newContentBuilder(attribution)
            .setTitle(title)
            .setStartIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .build()
        return InlinePresentation(content.slice, spec, false)
    }

    private fun walk(node: AssistStructure.ViewNode, f: Fields) {
        f.domain = f.domain ?: node.webDomain
        val id = node.autofillId
        if (id != null) {
            val v = node.autofillValue
            if (v != null && v.isText) f.values[id] = v.textValue.toString()
        }
        if (id != null && node.visibility == android.view.View.VISIBLE) {
            val hints = node.autofillHints?.map { it.lowercase() } ?: emptyList()
            val type = node.inputType
            val variation = type and InputType.TYPE_MASK_VARIATION
            val isText = (type and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT
            val isPass = hints.contains("password") ||
                (isText && (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD))
            val label = ((node.idEntry ?: "") + " " + (node.hint ?: "")).lowercase()
            val isUser = hints.any { it == "username" || it == "emailaddress" || it == "email" } ||
                (isText && variation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS) ||
                label.contains("user") || label.contains("email") || label.contains("login")

            if (isPass) {
                if (f.passId == null) f.passId = id
                if (f.userId == null) f.userId = f.lastText
            } else if (isText || node.className?.contains("EditText") == true) {
                if (isUser && f.userId == null && f.passId == null) f.userId = id
                f.lastText = id
            }
        }
        for (i in 0 until node.childCount) walk(node.getChildAt(i), f)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.last().structure
        val f = Fields()
        for (i in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(i).rootViewNode, f)
        }
        val pass = f.passId?.let { f.values[it] }
        val user = f.userId?.let { f.values[it] } ?: ""
        if (pass.isNullOrEmpty()) {
            callback.onSuccess()
            return
        }
        startActivity(
            Intent(this, AutofillActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(AutofillActivity.EXTRA_DOMAIN, f.domain)
                .putExtra(AutofillActivity.EXTRA_PACKAGE, structure.activityComponent?.packageName)
                .putExtra(AutofillActivity.EXTRA_SAVE, true)
                .putExtra(AutofillActivity.EXTRA_SAVE_USER, user)
                .putExtra(AutofillActivity.EXTRA_SAVE_PASS, pass)
        )
        callback.onSuccess()
    }
}
