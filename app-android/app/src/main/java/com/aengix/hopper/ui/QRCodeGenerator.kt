package com.aengix.hopper.ui

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

object QRCodeGenerator {
    fun encode(content: String, size: Int = 512): Bitmap? {
        return runCatching {
            val matrix = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, size, size)
            Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565).also { bitmap ->
                for (x in 0 until size) {
                    for (y in 0 until size) {
                        bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
                    }
                }
            }
        }.getOrNull()
    }
}
