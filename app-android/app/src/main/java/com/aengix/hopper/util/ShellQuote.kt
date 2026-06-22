package com.aengix.hopper.util

object ShellQuote {
    fun bashSingle(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"
}
