package com.example.self_control.apps

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import java.io.ByteArrayOutputStream
import java.util.Locale

class InstalledAppProvider(private val context: Context) {

    fun getInstalledApps(): List<Map<String, Any?>> {
        val packageManager = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val resolveInfos: List<ResolveInfo> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0L)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(launcherIntent, 0)
        }

        val ownPackageName = context.packageName
        val seenPackages = HashSet<String>()
        val appList = ArrayList<Map<String, Any?>>()

        for (info in resolveInfos) {
            val activityInfo = info.activityInfo ?: continue
            val packageName = activityInfo.packageName ?: continue

            if (packageName == ownPackageName || !seenPackages.add(packageName)) {
                continue
            }

            val appName = try {
                val label = info.loadLabel(packageManager).toString()
                if (label.isNotBlank()) label else packageName
            } catch (e: Exception) {
                packageName
            }

            val iconBytes = try {
                val iconDrawable = info.loadIcon(packageManager)
                drawableToByteArray(iconDrawable, targetSize = 96)
            } catch (t: Throwable) {
                null
            }

            appList.add(
                mapOf(
                    "packageName" to packageName,
                    "appName" to appName,
                    "icon" to iconBytes
                )
            )
        }

        appList.sortWith { a, b ->
            val nameA = (a["appName"] as? String).orEmpty().lowercase(Locale.ROOT)
            val nameB = (b["appName"] as? String).orEmpty().lowercase(Locale.ROOT)
            nameA.compareTo(nameB)
        }

        return appList
    }

    private fun drawableToByteArray(drawable: Drawable?, targetSize: Int = 96): ByteArray? {
        if (drawable == null) return null
        return try {
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else targetSize
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else targetSize

            val maxDim = maxOf(width, height)
            val scale = if (maxDim > targetSize) targetSize.toFloat() / maxDim else 1f
            val finalWidth = maxOf(1, (width * scale).toInt())
            val finalHeight = maxOf(1, (height * scale).toInt())

            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null &&
                drawable.intrinsicWidth <= targetSize && drawable.intrinsicHeight <= targetSize
            ) {
                drawable.bitmap
            } else {
                val bmp = Bitmap.createBitmap(finalWidth, finalHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (t: Throwable) {
            null
        }
    }
}
