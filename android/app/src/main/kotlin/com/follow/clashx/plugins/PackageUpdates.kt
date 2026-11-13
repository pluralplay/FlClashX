package com.follow.clashx.plugins

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import androidx.core.content.pm.PackageInfoCompat
import java.io.File
import java.security.MessageDigest

object PackageUpdates {
    fun statusAction(context: Context) = "${context.packageName}.PACKAGE_INSTALL_STATUS"

    fun inspectSelf(context: Context): Map<String, Any> {
        val info = packageInfo(context.packageManager, context.packageName)
        return describe(info)
    }

    fun inspectArchive(context: Context, path: String): Map<String, Any> {
        val info = archiveInfo(context.packageManager, path)
            ?: throw IllegalArgumentException("Not an installable package")
        return describe(info)
    }

    /**
     * The session is bound to this app's package name, so the installer
     * refuses any other package even if one got past the Dart checks.
     */
    /** The session a status broadcast has to name to be acted on. */
    @Volatile
    var activeSession: Int? = null
        private set

    fun install(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
        }
        val sessionId = installer.createSession(params)
        try {
            installer.openSession(sessionId).use { session ->
                apk.inputStream().use { input ->
                    session.openWrite("update.apk", 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                // The installer fills in the status extras, which an immutable intent would drop.
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val status = Intent(statusAction(context)).setPackage(context.packageName)
                activeSession = sessionId
                session.commit(
                    PendingIntent.getBroadcast(context, sessionId, status, flags).intentSender,
                )
            }
        } catch (error: Exception) {
            runCatching { installer.abandonSession(sessionId) }
            throw error
        }
    }

    private val signatureFlags =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

    private fun packageInfo(packageManager: PackageManager, packageName: String): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(signatureFlags.toLong()),
            )
        } else {
            packageManager.getPackageInfo(packageName, signatureFlags)
        }

    private fun archiveInfo(packageManager: PackageManager, path: String): PackageInfo? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                path,
                PackageManager.PackageInfoFlags.of(signatureFlags.toLong()),
            )
        } else {
            packageManager.getPackageArchiveInfo(path, signatureFlags)
        }

    private fun describe(info: PackageInfo): Map<String, Any> = mapOf(
        "packageName" to info.packageName,
        "versionCode" to PackageInfoCompat.getLongVersionCode(info),
        "signers" to signersOf(info).map { sha256Hex(it.toByteArray()) },
    )

    @Suppress("DEPRECATION")
    private fun signersOf(info: PackageInfo): List<Signature> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners?.toList().orEmpty()
        } else {
            info.signatures?.toList().orEmpty()
        }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it)
        }
}
