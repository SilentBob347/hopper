package com.aengix.hopper.util

import android.util.Log

object TunnelLog {
    private const val TAG = "Hopper"

    fun info(message: String) {
        Log.i(TAG, message)
    }

    fun error(message: String) {
        Log.e(TAG, message)
    }
}
