package com.example.aurarun_app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.aurarun_app/share"

    override fun getRenderMode(): RenderMode = RenderMode.texture
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.opaque

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "shareToInstagram" -> {
                        val imagePath = call.argument<String>("imagePath")
                        if (imagePath == null) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }
                        val success = shareToInstagramStories(imagePath)
                        result.success(success)
                    }

                    "shareToSnapchat" -> {
                        val imagePath = call.argument<String>("imagePath")
                        val attachmentUrl = call.argument<String>("attachmentUrl") ?: ""
                        if (imagePath == null) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }
                        val success = shareToSnapchatStories(imagePath, attachmentUrl)
                        result.success(success)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Instagram Stories ─────────────────────────────────────────────────────

    private fun shareToInstagramStories(imagePath: String): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) return false

            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )

            val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
                setDataAndType(uri, "image/png")
                // ✅ FLAG_ACTIVITY_NEW_TASK required when launching from non-Activity context
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("interactive_asset_uri", uri)
                putExtra("content_url", "https://strideun.app")
            }

            // ✅ Use resolveActivity instead of queryIntentActivities to avoid deprecation
            if (intent.resolveActivity(packageManager) == null) return false

            grantUriPermission(
                "com.instagram.android",
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    // ── Snapchat Stories ──────────────────────────────────────────────────────

    private fun shareToSnapchatStories(imagePath: String, attachmentUrl: String): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) return false

            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )

            val intent = Intent("com.snapchat.android.CREATIVE_KIT_ADD_TO_STORY").apply {
                putExtra("com.snapchat.android.intent.extra.STORY_IMAGE", uri)
                if (attachmentUrl.isNotEmpty()) {
                    putExtra(
                        "com.snapchat.android.intent.extra.ATTACHMENT_URL",
                        attachmentUrl
                    )
                }
                // ✅ FLAG_ACTIVITY_NEW_TASK required
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            // ✅ resolveActivity instead of queryIntentActivities
            if (intent.resolveActivity(packageManager) == null) return false

            grantUriPermission(
                "com.snapchat.android",
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}