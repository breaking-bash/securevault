package com.securevault.securevault

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.provider.PendingIntentHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec

/**
 * Hosts the Flutter UI for a passkey create/sign-in request. Flutter unlocks
 * the vault and stores/looks up the passkey; all WebAuthn encoding and ES256
 * signing happens here.
 */
class PasskeyActivity : FlutterFragmentActivity() {
    companion object {
        const val EXTRA_MODE = "sv_pk_mode"
    }

    private var mode = "get"
    private var rpId = ""
    private var rpName = ""
    private var userName = ""
    private var displayName = ""
    private var userHandle = ""
    private var challenge = ""
    private var clientDataHash: ByteArray? = null
    private var origin = ""
    private var callerPackage = ""
    private var pendingResponse: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        mode = intent.getStringExtra(EXTRA_MODE) ?: "get"
        try {
            if (mode == "create") parseCreate() else parseGet()
        } catch (e: Exception) {
            cancel()
        }
    }

    private fun parseCreate() {
        val req = PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent)
            ?: return cancel()
        val pk = req.callingRequest as? CreatePublicKeyCredentialRequest ?: return cancel()
        val json = JSONObject(pk.requestJson)
        val rp = json.getJSONObject("rp")
        val user = json.getJSONObject("user")
        rpId = rp.optString("id")
        rpName = rp.optString("name", rpId)
        userName = user.optString("name")
        displayName = user.optString("displayName", userName)
        userHandle = user.optString("id")
        challenge = json.getString("challenge")
        clientDataHash = pk.clientDataHash
        callerPackage = req.callingAppInfo.packageName
        origin = nativeOrigin(req.callingAppInfo)
        if (rpId.isEmpty()) cancel()
    }

    private fun parseGet() {
        val req = PendingIntentHandler.retrieveProviderGetCredentialRequest(intent)
            ?: return cancel()
        val opt = req.credentialOptions.filterIsInstance<GetPublicKeyCredentialOption>()
            .firstOrNull() ?: return cancel()
        val json = JSONObject(opt.requestJson)
        rpId = json.optString("rpId")
        challenge = json.getString("challenge")
        clientDataHash = opt.clientDataHash
        callerPackage = req.callingAppInfo.packageName
        origin = nativeOrigin(req.callingAppInfo)
        if (rpId.isEmpty()) cancel()
    }

    @Suppress("DEPRECATION")
    private fun nativeOrigin(info: androidx.credentials.provider.CallingAppInfo): String {
        return try {
            val signer = info.signingInfo.apkContentsSigners.first()
            "android:apk-key-hash:" + b64(sha256(signer.toByteArray()))
        } catch (e: Exception) {
            ""
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securevault/autofill")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getRequest" -> result.success(
                            mapOf(
                                "domain" to rpId,
                                "package" to callerPackage,
                                "save" to false,
                                "passkeyMode" to mode,
                                "rpId" to rpId,
                                "rpName" to rpName,
                                "userName" to userName,
                                "displayName" to displayName
                            )
                        )
                        "passkeyCreate" -> result.success(createPasskey())
                        "passkeyComplete" -> {
                            finishCreate()
                            result.success(null)
                        }
                        "passkeyAssert" -> {
                            assertPasskey(
                                call.argument<String>("privateKey") ?: "",
                                call.argument<String>("credentialId") ?: "",
                                call.argument<String>("userHandle") ?: ""
                            )
                            result.success(null)
                        }
                        "cancel" -> {
                            cancel()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("passkey", e.message, null)
                }
            }
    }

    private fun cancel() {
        val out = Intent()
        if (mode == "create") {
            PendingIntentHandler.setCreateCredentialException(out, CreateCredentialCancellationException())
        } else {
            PendingIntentHandler.setGetCredentialException(out, GetCredentialCancellationException())
        }
        setResult(Activity.RESULT_OK, out)
        finish()
    }

    // ------------------------------------------------------------ registration
    private fun clientData(type: String): Pair<ByteArray, ByteArray> {
        val given = clientDataHash
        if (given != null) return Pair(ByteArray(0), given)
        val bytes = JSONObject()
            .put("type", type)
            .put("challenge", challenge)
            .put("origin", origin)
            .put("androidPackageName", callerPackage)
            .toString().toByteArray()
        return Pair(bytes, sha256(bytes))
    }

    private fun createPasskey(): Map<String, String> {
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec("secp256r1"))
        val pair = gen.generateKeyPair()
        val pub = pair.public as ECPublicKey
        val x = fixed32(pub.w.affineX)
        val y = fixed32(pub.w.affineY)
        val credId = ByteArray(32).also { SecureRandom().nextBytes(it) }

        val cose = ByteArrayOutputStream().apply {
            write(byteArrayOf(0xA5.toByte(), 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20))
            write(x)
            write(byteArrayOf(0x22, 0x58, 0x20))
            write(y)
        }.toByteArray()

        // UP | UV | BE | BS | AT
        val authData = ByteArrayOutputStream().apply {
            write(sha256(rpId.toByteArray()))
            write(0x5D)
            write(ByteArray(4))
            write(ByteArray(16))
            write(byteArrayOf((credId.size shr 8).toByte(), credId.size.toByte()))
            write(credId)
            write(cose)
        }.toByteArray()

        val attestation = ByteArrayOutputStream().apply {
            write(0xA3)
            write(0x63); write("fmt".toByteArray())
            write(0x64); write("none".toByteArray())
            write(0x67); write("attStmt".toByteArray())
            write(0xA0)
            write(0x68); write("authData".toByteArray())
            write(0x59)
            write(authData.size shr 8)
            write(authData.size and 0xFF)
            write(authData)
        }.toByteArray()

        val (clientJson, _) = clientData("webauthn.create")
        pendingResponse = JSONObject()
            .put("id", b64(credId))
            .put("rawId", b64(credId))
            .put("type", "public-key")
            .put("authenticatorAttachment", "platform")
            .put(
                "response", JSONObject()
                    .put("clientDataJSON", b64(clientJson))
                    .put("attestationObject", b64(attestation))
                    .put("transports", JSONArray(listOf("internal", "hybrid")))
                    .put("publicKeyAlgorithm", -7)
                    .put("publicKey", b64(pub.encoded))
                    .put("authenticatorData", b64(authData))
            )
            .put("clientExtensionResults", JSONObject())
            .toString()

        return mapOf(
            "credentialId" to b64(credId),
            "privateKey" to b64(pair.private.encoded),
            "publicKey" to b64(pub.encoded),
            "userHandle" to userHandle
        )
    }

    private fun finishCreate() {
        val json = pendingResponse ?: return cancel()
        val out = Intent()
        PendingIntentHandler.setCreateCredentialResponse(out, CreatePublicKeyCredentialResponse(json))
        setResult(Activity.RESULT_OK, out)
        finish()
    }

    // --------------------------------------------------------------- sign-in
    private fun assertPasskey(privateKey: String, credentialId: String, handle: String) {
        val key = KeyFactory.getInstance("EC")
            .generatePrivate(PKCS8EncodedKeySpec(unb64(privateKey)))
        // UP | UV | BE | BS
        val authData = ByteArrayOutputStream().apply {
            write(sha256(rpId.toByteArray()))
            write(0x1D)
            write(ByteArray(4))
        }.toByteArray()
        val (clientJson, hash) = clientData("webauthn.get")
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(authData)
            update(hash)
            sign()
        }
        val json = JSONObject()
            .put("id", credentialId)
            .put("rawId", credentialId)
            .put("type", "public-key")
            .put("authenticatorAttachment", "platform")
            .put(
                "response", JSONObject()
                    .put("clientDataJSON", b64(clientJson))
                    .put("authenticatorData", b64(authData))
                    .put("signature", b64(signature))
                    .put("userHandle", handle)
            )
            .put("clientExtensionResults", JSONObject())
            .toString()
        val out = Intent()
        PendingIntentHandler.setGetCredentialResponse(
            out, GetCredentialResponse(PublicKeyCredential(json))
        )
        setResult(Activity.RESULT_OK, out)
        finish()
    }

    // ----------------------------------------------------------------- helpers
    private fun sha256(b: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(b)

    private fun b64(b: ByteArray): String =
        Base64.encodeToString(b, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

    private fun unb64(s: String): ByteArray = Base64.decode(s, Base64.URL_SAFE or Base64.NO_PADDING)

    private fun fixed32(v: BigInteger): ByteArray {
        val raw = v.toByteArray()
        val out = ByteArray(32)
        val len = minOf(raw.size, 32)
        System.arraycopy(raw, raw.size - len, out, 32 - len, len)
        return out
    }
}
