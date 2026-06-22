package com.aengix.hopper.data

import com.aengix.hopper.model.HopNodeProfile

object HopQRExporter {
    fun exportJson(profile: HopNodeProfile): String =
        HopProfileCodec.exportJson(profile).toString(2)
}
