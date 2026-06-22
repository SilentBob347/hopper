from __future__ import annotations

import html
import json
from pathlib import Path


def write_qr_html(out_path: Path, payload_raw: str, host: str) -> None:
    payload_obj = json.loads(payload_raw)
    payload_compact = json.dumps(payload_obj, separators=(",", ":"))
    payload_pretty = json.dumps(payload_obj, indent=2)
    payload_js = json.dumps(payload_compact)
    payload_pretty_js = json.dumps(payload_pretty)
    title = f"Hopper — {host}"
    doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js" crossorigin="anonymous"></script>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; min-height: 100vh; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 1.25rem; padding: 1.5rem;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #1b2f4b; color: #e8f5e9;
    }}
    h1 {{ margin: 0; font-size: 1.25rem; font-weight: 600; }}
    p {{ margin: 0; max-width: 42rem; text-align: center; opacity: 0.85; font-size: 0.9rem; }}
    .panel {{
      display: flex; flex-wrap: wrap; align-items: flex-start; justify-content: center;
      gap: 1.5rem; max-width: 56rem; width: 100%;
    }}
    #qrcode {{
      padding: 1rem; background: #fff; border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.35); flex: 0 0 auto;
    }}
    .json-block {{
      flex: 1 1 18rem; min-width: 0; display: flex; flex-direction: column; gap: 0.5rem;
    }}
    .json-toolbar {{
      display: flex; align-items: center; justify-content: space-between; gap: 0.75rem;
    }}
    .json-toolbar span {{ font-size: 0.85rem; opacity: 0.85; }}
    button {{
      border: none; border-radius: 8px; padding: 0.45rem 0.85rem;
      font: inherit; font-size: 0.85rem; cursor: pointer;
      background: #4caf50; color: #fff;
    }}
    button:hover {{ background: #43a047; }}
    button.copied {{ background: #2e7d32; }}
    textarea {{
      width: 100%; min-height: 18rem; margin: 0; padding: 0.75rem 1rem;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.72rem; line-height: 1.45; resize: vertical;
      background: rgba(0,0,0,0.25); color: #e8f5e9; border: 1px solid rgba(255,255,255,0.12);
      border-radius: 8px;
    }}
  </style>
</head>
<body>
  <h1>Hopper — scan or copy JSON</h1>
  <p>Add in chain order: entry → exit. Scan the QR in the app, or copy the JSON and use Import JSON.</p>
  <div class="panel">
    <div id="qrcode"></div>
    <div class="json-block">
      <div class="json-toolbar">
        <span>Hop config JSON</span>
        <button type="button" id="copy-btn">Copy JSON</button>
      </div>
      <textarea id="payload" readonly spellcheck="false"></textarea>
    </div>
  </div>
  <script>
    const payload = {payload_js};
    const payloadPretty = {payload_pretty_js};
    const textarea = document.getElementById("payload");
    const copyBtn = document.getElementById("copy-btn");
    textarea.value = payloadPretty;
    copyBtn.addEventListener("click", async () => {{
      try {{
        await navigator.clipboard.writeText(payloadPretty);
        copyBtn.textContent = "Copied!";
        copyBtn.classList.add("copied");
        setTimeout(() => {{
          copyBtn.textContent = "Copy JSON";
          copyBtn.classList.remove("copied");
        }}, 1600);
      }} catch (err) {{
        textarea.focus();
        textarea.select();
        document.execCommand("copy");
      }}
    }});
    new QRCode(document.getElementById("qrcode"), {{
      text: payload,
      width: 320,
      height: 320,
      correctLevel: QRCode.CorrectLevel.M,
    }});
  </script>
</body>
</html>
"""
    out_path.write_text(doc)
