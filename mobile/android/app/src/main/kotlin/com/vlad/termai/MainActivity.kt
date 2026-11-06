package com.vlad.termai

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Нативный мост к системному DownloadManager.
 *
 * DownloadManager выбран специально: он переживает сворачивание приложения,
 * убийство процесса и перезагрузку устройства. Ручной паузы у него нет,
 * поэтому UI показывает только отмену и повтор.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.vlad.termai/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "enqueue" -> {
                            val url = call.argument<String>("url") ?: ""
                            val fileName = call.argument<String>("fileName") ?: ""
                            val headers =
                                call.argument<Map<String, String>>("headers") ?: emptyMap()
                            val expected =
                                (call.argument<Number>("expectedBytes") ?: 0).toLong()
                            if (url.isEmpty() || fileName.isEmpty()) {
                                result.error("bad_args", "url and fileName are required", null)
                                return@setMethodCallHandler
                            }
                            result.success(enqueue(url, fileName, headers, expected))
                        }
                        "status" -> {
                            val id = (call.argument<Number>("id") ?: 0).toLong()
                            val finalPath = call.argument<String>("finalPath") ?: ""
                            result.success(status(id, finalPath))
                        }
                        "cancel" -> {
                            val id = (call.argument<Number>("id") ?: 0).toLong()
                            val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            result.success(dm.remove(id))
                        }
                        "modelsDir" -> result.success(modelsDir().absolutePath)
                        "freeSpace" -> {
                            val stat = StatFs(modelsDir().absolutePath)
                            result.success(stat.availableBytes)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("download_error", e.message ?: "download error", null)
                }
            }
    }

    private fun modelsDir(): File {
        val dir = File(getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "models")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun safeName(name: String): String {
        val base = name.substringAfterLast('/')
        return base.replace(Regex("[^a-zA-Z0-9._-]"), "_")
    }

    private fun enqueue(
        url: String,
        fileName: String,
        headers: Map<String, String>,
        expected: Long,
    ): Map<String, Any> {
        val dir = modelsDir()
        val target = File(dir, safeName(fileName))
        val part = File(dir, "${safeName(fileName)}.part")
        if (target.exists() && target.length() > 0L) {
            // Не запускаем повторную загрузку уже существующего файла.
            if (expected <= 0L || target.length() == expected) {
                return mapOf(
                    "alreadyExists" to true,
                    "path" to target.absolutePath,
                    "size" to target.length(),
                )
            }
            // Неполный/чужой файл не трогаем молча: сообщаем размер наверх.
            return mapOf(
                "alreadyExists" to true,
                "path" to target.absolutePath,
                "size" to target.length(),
            )
        }

        if (part.exists()) {
            // Незавершённый файл от прошлой попытки не должен выглядеть
            // установленной моделью. Новая попытка начинает его заново.
            part.delete()
        }
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(safeName(fileName))
            .setDescription("TERMAI · локальная модель")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalFilesDir(
                applicationContext,
                Environment.DIRECTORY_DOWNLOADS,
                "models/${safeName(fileName)}.part",
            )
        for ((key, value) in headers) {
            request.addRequestHeader(key, value)
        }
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val id = dm.enqueue(request)
        return mapOf(
            "systemId" to id,
            "path" to target.absolutePath,
        )
    }

    private fun status(id: Long, finalPath: String): Map<String, Any?> {
        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = dm.query(DownloadManager.Query().setFilterById(id))
        if (cursor == null) {
            return mapOf("status" to "failed", "reason" to -1)
        }
        cursor.use {
            if (!it.moveToFirst()) {
                return mapOf("status" to "failed", "reason" to -1)
            }
            val state = it.getInt(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS),
            )
            val received = it.getLong(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
            )
            val total = it.getLong(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
            )
            val reason = it.getInt(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON),
            )
            val localUri = it.getString(
                it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI),
            )
            val status = when (state) {
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_RUNNING -> "running"
                else -> "pending"
            }
            var path = localUri
                ?.removePrefix("file://")
                ?.let { Uri.decode(it) }
                ?: ""
            if (status == "successful" && finalPath.isNotEmpty()) {
                val target = File(finalPath)
                val sourceUri = localUri?.let { Uri.parse(it) }
                val part = if (sourceUri?.scheme == "file") {
                    sourceUri.path?.let { File(it) }
                } else null
                try {
                    target.parentFile?.mkdirs()
                    if (part?.exists() == true) {
                        if (target.exists()) target.delete()
                        if (!part.renameTo(target)) {
                            part.inputStream().use { input ->
                                FileOutputStream(target).use { output -> input.copyTo(output) }
                            }
                            part.delete()
                        }
                    } else if (!target.exists()) {
                        // На части Android DownloadManager возвращает content://,
                        // а не файловый путь. Копируем через resolver, при отказе
                        // resolver'а — через openDownloadedFile.
                        val input = runCatching {
                            sourceUri?.let { contentResolver.openInputStream(it) }
                        }.getOrNull()
                            ?: dm.openDownloadedFile(id)?.let {
                                android.os.ParcelFileDescriptor.AutoCloseInputStream(it)
                            }
                        input?.use { source ->
                            FileOutputStream(target).use { output -> source.copyTo(output) }
                        } ?: throw java.io.IOException("не удалось открыть скачанный файл")
                    }
                } catch (e: Exception) {
                    // Если файл уже на месте и не пустой — считаем загрузку
                    // успешной: раньше любое исключение здесь «зависало»
                    // прогресс на последних процентах.
                    if (!target.exists() || target.length() == 0L) {
                        return mapOf(
                            "status" to "failed",
                            "reason" to -2,
                            "message" to (e.message ?: e.javaClass.simpleName),
                            "path" to target.absolutePath,
                            "received" to received.coerceAtLeast(0L),
                            "total" to total.coerceAtLeast(0L),
                        )
                    }
                }
                if (target.exists()) path = target.absolutePath
            }
            return mapOf(
                "status" to status,
                "received" to received.coerceAtLeast(0L),
                "total" to total.coerceAtLeast(0L),
                "reason" to reason,
                "path" to path,
            )
        }
    }
}
