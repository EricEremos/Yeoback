#!/usr/bin/env python3
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent
assets = root / "Yeoback/Assets.xcassets"
assets.mkdir(parents=True, exist_ok=True)
info = {"author": "xcode", "version": 1}
(assets / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
for name, light, dark in [
    ("Paper", "F5F3EF", "1D1F1E"), ("Ink", "252C27", "F1EEE8"),
    ("Muted", "62675F", "B8BDB4"), ("Line", "C5C9BF", "535D52"),
    ("Accent", "AE3529", "FF9988"), ("Tint", "E6E9E1", "353A35"),
    ("Surface", "FFFEFA", "252725"),
]:
    folder = assets / (name + ".colorset")
    folder.mkdir(exist_ok=True)
    colors = []
    for mode, value in [("light", light), ("dark", dark)]:
        color = {"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": "0x" + value[:2], "green": "0x" + value[2:4], "blue": "0x" + value[4:], "alpha": "1.000"}}}
        if mode == "dark":
            color["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        colors.append(color)
    (folder / "Contents.json").write_text(json.dumps({"colors": colors, "info": info}, indent=2) + "\n")
icon = assets / "AppIcon.appiconset"
icon.mkdir(exist_ok=True)
shutil.copyfile(root.parent.parent / "Resources/Brand/Yeoback-icon-1024.png", icon / "Yeoback.png")
(icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "Yeoback.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": info}, indent=2) + "\n")
