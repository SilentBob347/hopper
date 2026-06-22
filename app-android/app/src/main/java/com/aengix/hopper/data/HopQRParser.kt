package com.aengix.hopper.data

import com.aengix.hopper.model.HopNodeProfile

object HopQRParser {
    sealed class ParseError(message: String) : Exception(message) {
        data object EmptyPayload : ParseError("The QR code is empty.")
        data object InvalidJson : ParseError("The QR code contains invalid JSON.")
        data object MissingHost : ParseError("The hop config is missing a host.")
        data object MissingUser : ParseError("The hop config is missing a user.")
        data object MissingPrivateKey : ParseError("The hop config is missing a private key.")
    }

    fun parse(payload: String): HopNodeProfile = HopProfileCodec.parse(payload)
}
