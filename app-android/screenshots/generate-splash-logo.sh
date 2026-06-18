#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG="#18594C"
ICON="$ROOT/../screenshots/app-icon.png"
OUT="$ROOT/app/src/main/res/drawable/splash_logo.png"
SIZE=512

python3 - "$BG" "$ICON" "$OUT" "$SIZE" <<'PY'
import sys
from PIL import Image

bg_hex, icon_path, out_path, size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
bg = tuple(int(bg_hex[i:i + 2], 16) for i in (1, 3, 5))

icon = Image.open(icon_path).convert("RGBA")
target = int(size * 0.76)
icon = icon.resize((target, target), Image.Resampling.LANCZOS)

canvas = Image.new("RGBA", (size, size), bg + (255,))
x = (size - target) // 2
y = (size - target) // 2
flat = Image.new("RGBA", (target, target), bg + (255,))
flat.paste(icon, (0, 0), icon)
canvas.paste(flat, (x, y))
canvas.save(out_path, "PNG")
print(f"Saved {out_path} ({size}x{size}, bg {bg_hex})")
PY
