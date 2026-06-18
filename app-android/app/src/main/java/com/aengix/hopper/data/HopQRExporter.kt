package com.aengix.hopper.data

import com.aengix.hopper.model.HopNodeProfile
import org.json.JSONArray
import org.json.JSONObject

object HopQRExporter {
    fun exportJson(profile: HopNodeProfile): String {
        val json = JSONObject()
        json.put("v", 2)
        json.put("host", profile.trimmedHost)
        json.put("port", profile.port.toString())
        json.put("user", profile.trimmedUser)
        json.put("private_key", profile.privateKey)

        if (profile.trimmedName.isNotEmpty()) {
            json.put("name", profile.trimmedName)
        }
        if (profile.hostKeys.isNotEmpty()) {
            json.put("host_key", JSONArray(profile.hostKeys))
        }
        val install = profile.installDir.trim()
        if (install.isNotEmpty()) {
            json.put("install_dir", install)
        }

        return json.toString(2)
    }
}
