package com.aengix.hopper.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aengix.hopper.data.HopQRParser
import com.aengix.hopper.model.HopNodeProfile

@Composable
fun ImportJsonDialog(
    onDismiss: () -> Unit,
    onImport: (HopNodeProfile) -> Unit,
    onError: (String) -> Unit,
) {
    var jsonText by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Import JSON") },
        text = {
            OutlinedTextField(
                value = jsonText,
                onValueChange = { jsonText = it },
                label = { Text("Hop config JSON") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp),
            )
            errorMessage?.let {
                Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    errorMessage = null
                    runCatching { HopQRParser.parse(jsonText) }
                        .onSuccess(onImport)
                        .onFailure { error ->
                            errorMessage = error.message
                            onError(error.message ?: "Import failed")
                        }
                },
                enabled = jsonText.trim().isNotEmpty(),
            ) { Text("Import") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
