package com.securevault.securevault

import android.app.PendingIntent
import android.content.Intent
import android.os.CancellationSignal
import android.os.OutcomeReceiver
import androidx.annotation.RequiresApi
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialUnknownException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.provider.BeginCreateCredentialRequest
import androidx.credentials.provider.BeginCreateCredentialResponse
import androidx.credentials.provider.BeginCreatePublicKeyCredentialRequest
import androidx.credentials.provider.BeginGetCredentialRequest
import androidx.credentials.provider.BeginGetCredentialResponse
import androidx.credentials.provider.BeginGetPublicKeyCredentialOption
import androidx.credentials.provider.CreateEntry
import androidx.credentials.provider.CredentialProviderService
import androidx.credentials.provider.ProviderClearCredentialStateRequest
import androidx.credentials.provider.PublicKeyCredentialEntry

/**
 * Passkey provider for Android's Credential Manager (Android 14+). The vault is
 * encrypted, so this service only offers entries; the actual work happens in
 * [PasskeyActivity] after the user unlocks SecureVault.
 */
@RequiresApi(34)
class SecureVaultCredentialService : CredentialProviderService() {

    private fun pending(mode: String, code: Int): PendingIntent {
        val intent = Intent(this, PasskeyActivity::class.java)
            .setPackage(packageName)
            .putExtra(PasskeyActivity.EXTRA_MODE, mode)
        return PendingIntent.getActivity(
            this, code, intent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    override fun onBeginCreateCredentialRequest(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, CreateCredentialException>
    ) {
        if (request !is BeginCreatePublicKeyCredentialRequest) {
            callback.onError(CreateCredentialUnknownException())
            return
        }
        callback.onResult(
            BeginCreateCredentialResponse.Builder()
                .addCreateEntry(CreateEntry("SecureVault", pending("create", 1)))
                .build()
        )
    }

    override fun onBeginGetCredentialRequest(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, GetCredentialException>
    ) {
        val response = BeginGetCredentialResponse.Builder()
        for (option in request.beginGetCredentialOptions) {
            if (option is BeginGetPublicKeyCredentialOption) {
                response.addCredentialEntry(
                    PublicKeyCredentialEntry(
                        this, "Passkeys in SecureVault", pending("get", 2), option
                    )
                )
            }
        }
        callback.onResult(response.build())
    }

    override fun onClearCredentialStateRequest(
        request: ProviderClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, ClearCredentialException>
    ) {
        callback.onResult(null)
    }
}
