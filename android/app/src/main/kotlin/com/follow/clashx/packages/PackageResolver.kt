package com.follow.clashx.packages

import android.Manifest
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import com.follow.clashx.models.InstalledPackage

internal class PackageResolver(
    private val packageManager: PackageManager,
    private val appPackageName: String,
) {
    private val cacheLock = Any()

    @Volatile
    private var cachedPackages: List<InstalledPackage>? = null

    val installedPackages: List<InstalledPackage>
        get() = cachedPackages ?: synchronized(cacheLock) {
            cachedPackages ?: loadPackages().also { cachedPackages = it }
        }

    val isInstalledAppsPermissionSupported: Boolean by lazy {
        runCatching { packageManager.getPermissionInfo(GET_INSTALLED_APPS, 0) }.isSuccess
    }

    fun hasInstalledAppsPermission(): Boolean = !isInstalledAppsPermissionSupported ||
        packageManager.checkPermission(GET_INSTALLED_APPS, appPackageName) ==
        PackageManager.PERMISSION_GRANTED

    fun invalidate() {
        synchronized(cacheLock) { cachedPackages = null }
    }

    private fun loadPackages(): List<InstalledPackage> {
        val flags = PackageManager.GET_PERMISSIONS
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledPackages(
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledPackages(flags)
        }
        return packages.asSequence()
            .filter { info ->
                info.packageName != appPackageName && info.packageName != ANDROID_PACKAGE_NAME
            }
            .map { info ->
                InstalledPackage(
                    packageName = info.packageName,
                    label = info.applicationInfo?.loadLabel(packageManager)?.toString()
                        ?: info.packageName,
                    system = info.applicationInfo?.let { applicationInfo ->
                        applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0
                    } == true,
                    internet = info.requestedPermissions
                        ?.contains(Manifest.permission.INTERNET) == true,
                    lastUpdateTime = info.lastUpdateTime,
                )
            }.toList()
    }

    companion object {
        const val GET_INSTALLED_APPS = "com.android.permission.GET_INSTALLED_APPS"

        private const val ANDROID_PACKAGE_NAME = "android"
    }
}
