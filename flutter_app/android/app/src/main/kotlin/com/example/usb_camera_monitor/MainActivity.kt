package com.example.usb_camera_monitor

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.IOException


class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.example.usb_camera_monitor/usb"
        private const val ENCODER_CHANNEL = "com.example.usb_camera_monitor/encoder"
        private const val ACTION_USB_PERMISSION = "com.example.usb_camera_monitor.USB_PERMISSION"
        private const val CAMERA_PERMISSION_REQUEST = 1001
    }

    private var usbManager: UsbManager? = null
    private var pendingUsbDevice: UsbDevice? = null
    private var resultCallback: MethodChannel.Result? = null

    // UVC camera class/subclass identifiers
    private fun isUvcDevice(device: UsbDevice): Boolean {
        // USB Video Class (UVC) = Class 14 (0x0E)
        if (device.getInterface(0)?.interfaceClass == 14) return true
        // Check all interfaces
        for (i in 0 until device.interfaceCount) {
            if (device.getInterface(i)?.interfaceClass == 14) return true
        }
        // Also check subclasses
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i) ?: continue
            val sc = iface.interfaceSubclass
            // Video Control = 1, Video Streaming = 2
            if (sc == 1 || sc == 2) return true
        }
        return false
    }

    // Helper to check if it looks like a camera
    private fun isCameraDevice(device: UsbDevice): Boolean {
        val name = (device.productName ?: device.manufacturerName ?: "").lowercase()
        val cameraKeywords = listOf("camera", "cam", "webcam", "video", "capture",
            "brio", "c920", "c930", "c922", "c270", "lifecam", "obsbot", "insta360",
            "elgato", "avermedia", "uvc", "easycamera", "镜头", "摄像头")
        return cameraKeywords.any { name.contains(it) } || isUvcDevice(device)
    }

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            if (ACTION_USB_PERMISSION == intent.action) {
                synchronized(this) {
                    val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val cb = resultCallback
                    resultCallback = null
                    if (granted && device != null) {
                        cb?.success("granted:${device.deviceName}")
                    } else {
                        cb?.error("PERMISSION_DENIED", "USB permission denied", null)
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager

        // Register USB permission receiver
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(usbPermissionReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(usbPermissionReceiver)
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectUsbDevices" -> detectUsbDevices(result)
                    "requestUsbPermission" -> {
                        val deviceName = call.argument<String>("deviceName")
                        requestUsbPermission(deviceName, result)
                    }
                    "requestCameraPermission" -> requestCameraPermission(result)
                    "getDeviceInfo" -> getDeviceInfo(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENCODER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "encode" -> {
                        val framesDir = call.argument<String>("framesDir")
                        val outputPath = call.argument<String>("outputPath")
                        val fps = call.argument<Int>("fps") ?: 24
                        if (framesDir == null || outputPath == null) {
                            result.error("INVALID_ARG", "framesDir and outputPath required", null)
                            return@setMethodCallHandler
                        }
                        // 编码可能耗时（数百帧），放到后台线程，避免阻塞 Flutter UI。
                        Thread {
                            try {
                                val out = encodeFrames(framesDir, outputPath, fps)
                                result.success(out)
                            } catch (e: Exception) {
                                result.error("ENCODE_FAILED", e.message, e.toString())
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun detectUsbDevices(@NonNull result: MethodChannel.Result) {
        try {
            val manager = usbManager ?: run {
                result.success(listOf<Map<String, Any>>())
                return
            }
            val deviceList = manager.deviceList
            val devices = mutableListOf<Map<String, Any>>()

            for ((name, device) in deviceList) {
                val info = mutableMapOf<String, Any>(
                    "deviceName" to name,
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "deviceClass" to device.deviceClass,
                    "deviceSubclass" to device.deviceSubclass,
                    "manufacturerName" to (device.manufacturerName ?: "Unknown"),
                    "productName" to (device.productName ?: "Unknown"),
                    "serialNumber" to (device.serialNumber ?: "N/A"),
                    "interfaceCount" to device.interfaceCount,
                    "isUvc" to isUvcDevice(device),
                    "isCamera" to isCameraDevice(device),
                    "hasPermission" to manager.hasPermission(device),
                )

                // Collect interface info
                val interfaces = mutableListOf<Map<String, Any>>()
                for (i in 0 until device.interfaceCount) {
                    val iface = device.getInterface(i) ?: continue
                    interfaces.add(mapOf(
                        "index" to i,
                        "interfaceClass" to iface.interfaceClass,
                        "interfaceSubclass" to iface.interfaceSubclass,
                        "interfaceProtocol" to iface.interfaceProtocol,
                    ))
                }
                info["interfaces"] = interfaces
                devices.add(info)
            }

            result.success(devices)
        } catch (e: Exception) {
            result.error("USB_ERROR", e.message, e.toString())
        }
    }

    private fun requestUsbPermission(deviceName: String?, @NonNull result: MethodChannel.Result) {
        if (deviceName == null) {
            result.error("INVALID_ARG", "deviceName is required", null)
            return
        }

        val manager = usbManager ?: run {
            result.error("USB_UNAVAILABLE", "USB service not available", null)
            return
        }

        val device = manager.deviceList[deviceName]
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "USB device not found: $deviceName", null)
            return
        }

        if (manager.hasPermission(device)) {
            result.success("already_granted:${device.deviceName}")
            return
        }

        pendingUsbDevice = device
        resultCallback = result

        val permissionIntent = PendingIntent.getBroadcast(
            this, 0,
            Intent(ACTION_USB_PERMISSION).apply {
                setPackage(packageName)
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        manager.requestPermission(device, permissionIntent)
    }

    private fun requestCameraPermission(@NonNull result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }

        val perm = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
        if (perm == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }

        // Request permission
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST
        )
        result.success(false)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            // Notify through method channel will happen via callback
        }
    }

    private fun getDeviceInfo(@NonNull result: MethodChannel.Result) {
        result.success(mapOf(
            "sdkVersion" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "brand" to Build.BRAND,
            "device" to Build.DEVICE,
            "hasUsbHost" to (packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)),
            "hasUsbAccessory" to (packageManager.hasSystemFeature(PackageManager.FEATURE_USB_ACCESSORY)),
            "hasCamera" to (packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA)),
            "hasCameraExternal" to (packageManager.hasSystemFeature("android.hardware.camera.external")),
        ))
    }

    // ──────────────────────────────────────────────────────────────
    // UVC 录像：把抓取的 JPEG 帧序列编码为 H.264 MP4（MediaCodec + MediaMuxer）。
    // 不依赖任何第三方库，兼容所有仍受支持的 Flutter 嵌入层（v2）。
    // ──────────────────────────────────────────────────────────────
    private fun encodeFrames(framesDir: String, outputPath: String, fps: Int): String {
        val dir = File(framesDir)
        val files = dir.listFiles { f ->
            val ext = f.extension.lowercase()
            ext == "jpg" || ext == "jpeg"
        }?.sortedBy { it.name }
        if (files == null || files.isEmpty()) {
            throw IOException("No JPEG frames found in $framesDir")
        }

        // 读取首帧尺寸并对齐到偶数（MediaCodec 硬性要求宽高为偶数）。
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(files[0].absolutePath, boundsOpts)
        var width = boundsOpts.outWidth
        var height = boundsOpts.outHeight
        if (width <= 0 || height <= 0) throw IOException("Invalid frame size")
        if (width % 2 != 0) width -= 1
        if (height % 2 != 0) height -= 1

        val mime = "video/avc"
        val encoder = MediaCodec.createEncoderByType(mime)
        val colorFormat = selectYuvColorFormat(encoder, mime)
        val bitrate = (width * height * fps * 0.15).toInt().coerceIn(1_000_000, 12_000_000)
        val format = MediaFormat.createVideoFormat(mime, width, height).apply {
            setInteger("color-format", colorFormat)
            setInteger("bitrate", bitrate)
            setInteger("frame-rate", fps)
            setInteger("i-frame-interval", 1)
        }
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        encoder.start()

        var muxer: MediaMuxer? = null
        var muxerStarted = false
        var trackIndex = -1
        val bufferInfo = MediaCodec.BufferInfo()
        val frameIntervalUs = 1_000_000L / fps.coerceAtLeast(1)
        var frameIndex = 0
        var inputDone = false
        var idleCount = 0
        val timeoutUs = 10_000L

        try {
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            while (true) {
                if (!inputDone) {
                    val inIdx = encoder.dequeueInputBuffer(timeoutUs)
                    if (inIdx >= 0) {
                        if (frameIndex < files.size) {
                            val bitmap = decodeScaled(files[frameIndex].absolutePath, width, height)
                            val yuv = yuvFromBitmap(bitmap, colorFormat)
                            bitmap.recycle()
                            val inputBuffer = encoder.getInputBuffer(inIdx)!!
                            inputBuffer.clear()
                            inputBuffer.put(yuv)
                            val pts = frameIndex * frameIntervalUs
                            encoder.queueInputBuffer(inIdx, 0, yuv.size, pts, 0)
                            frameIndex++
                        } else {
                            encoder.queueInputBuffer(
                                inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        }
                    }
                }

                val outIdx = encoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                when {
                    outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        idleCount++
                        if (idleCount > 100) break // 兜底：异常情况下避免死循环
                        continue
                    }
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (!muxerStarted) {
                            trackIndex = muxer!!.addTrack(encoder.outputFormat)
                            muxer!!.start()
                            muxerStarted = true
                        }
                    }
                    outIdx >= 0 -> {
                        idleCount = 0
                        if (!muxerStarted) {
                            trackIndex = muxer!!.addTrack(encoder.outputFormat)
                            muxer!!.start()
                            muxerStarted = true
                        }
                        val outBuffer = encoder.getOutputBuffer(outIdx)!!
                        if (bufferInfo.size > 0) {
                            outBuffer.position(bufferInfo.offset)
                            outBuffer.limit(bufferInfo.offset + bufferInfo.size)
                            muxer!!.writeSampleData(trackIndex, outBuffer, bufferInfo)
                        }
                        encoder.releaseOutputBuffer(outIdx, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    }
                }
            }
        } finally {
            try { encoder.stop() } catch (_: Exception) {}
            try { encoder.release() } catch (_: Exception) {}
            try { if (muxerStarted) muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }

        val outFile = File(outputPath)
        if (!outFile.exists() || outFile.length() == 0L) {
            throw IOException("Encoder produced no output at $outputPath")
        }
        return outputPath
    }

    private fun selectYuvColorFormat(encoder: MediaCodec, mime: String): Int {
        val caps = encoder.codecInfo.getCapabilitiesForType(mime)
        val formats = caps.colorFormats
        val preferred = listOf(
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
        )
        for (f in preferred) {
            if (formats.contains(f)) return f
        }
        return MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
    }

    private fun decodeScaled(path: String, width: Int, height: Int): Bitmap {
        val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        val raw = BitmapFactory.decodeFile(path, opts)
            ?: throw IOException("Failed to decode frame: $path")
        if (raw.width == width && raw.height == height) return raw
        val scaled = Bitmap.createScaledBitmap(raw, width, height, true)
        raw.recycle()
        return scaled
    }

    private fun yuvFromBitmap(bitmap: Bitmap, colorFormat: Int): ByteArray {
        return when (colorFormat) {
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible ->
                argbToSemiPlanar(bitmap, uvOrder = 1) // NV12 (UV)
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar ->
                argbToSemiPlanar(bitmap, uvOrder = 0) // 近似 NV21
            else ->
                argbToSemiPlanar(bitmap, uvOrder = 0) // NV21 (VU)
        }
    }

    private fun argbToSemiPlanar(bitmap: Bitmap, uvOrder: Int): ByteArray {
        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        val ySize = w * h
        val out = ByteArray(ySize + ySize / 2)
        var yIdx = 0
        var uvIdx = ySize
        for (y in 0 until h) {
            for (x in 0 until w) {
                val p = pixels[y * w + x]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                val yVal = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                out[yIdx++] = yVal.coerceIn(0, 255).toByte()
                if (y % 2 == 0 && x % 2 == 0) {
                    val uVal = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val vVal = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    if (uvOrder == 0) {
                        // NV21: V 在前，U 在后
                        out[uvIdx++] = vVal.coerceIn(0, 255).toByte()
                        out[uvIdx++] = uVal.coerceIn(0, 255).toByte()
                    } else {
                        // NV12: U 在前，V 在后
                        out[uvIdx++] = uVal.coerceIn(0, 255).toByte()
                        out[uvIdx++] = vVal.coerceIn(0, 255).toByte()
                    }
                }
            }
        }
        return out
    }
}
