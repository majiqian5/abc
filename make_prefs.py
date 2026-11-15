#!/usr/bin/env python3
import plistlib, os, sys
out = sys.argv[1] if len(sys.argv) > 1 else "out"
B = os.path.join(out, "WeatherLockPrefs.bundle")
os.makedirs(B, exist_ok=True)
dom = "com.axs.weatherlock"

def group(label, footer=None):
    d = {"cell": "PSGroupCell", "label": label}
    if footer:
        d["footerText"] = footer
    return d

def text(k, label, default="", ph=None):
    d = {"cell": "PSTextFieldCell", "key": k, "defaults": dom, "label": label, "default": default}
    if ph:
        d["placeholder"] = ph
    return d

def slider(k, label, lo, hi, default):
    return {"cell": "PSSliderCell", "key": k, "defaults": dom, "label": label,
            "default": default, "min": lo, "max": hi}

def switch(k, label, default=True):
    return {"cell": "PSSwitchCell", "key": k, "defaults": dom, "defaultsDomain": dom,
            "label": label, "default": default}

specs = [
    group("彩云数据", "token 约 20 位；留空时锁屏会提示“还没填彩云 token”"),
    text("token", "彩云 token", "", "在此粘贴你的彩云 token"),
    text("city", "城市名", "南宁"),
    text("lat", "纬度", "22.8170"),
    text("lon", "经度", "108.3665"),

    group("文字"),
    slider("size", "主行字号", 8, 30, 14),
    slider("huespan", "彩虹跨度", 0.05, 1.0, 0.22),
    slider("bright", "亮度", 0.3, 1.0, 0.68),
    text("colorhex", "纯色（留空=彩虹）", "", "#FF8800"),

    group("位置与尺寸"),
    slider("offx", "水平偏移", -200, 200, 0),
    slider("offy", "距顶部", -100, 500, 120),
    slider("width", "宽度（999=全宽）", 200, 999, 999),
    slider("height", "高度", 50, 300, 108),
    slider("pad", "内边距", 0, 40, 12),
    slider("gap", "行距", 0, 12, 3),
    slider("radius", "圆角", 0, 40, 18),

    group("背景"),
    switch("bgweather", "背景跟随天气", True),
    slider("alpha", "背景不透明度", 0, 1, 0.9),
    text("bghex", "纯色背景（留空=自动）", "", "#101018"),

    group("内容"),
    switch("hourly", "显示未来 3 小时", True),
    switch("daily", "显示今日高低 / 日出日落", True),
]

info = {
    "CFBundleIdentifier": "com.axs.weatherlockprefs",
    "CFBundleName": "锁屏天气",
    "CFBundleExecutable": "WeatherLockPrefs",
    "CFBundlePackageType": "BNDL",
    "CFBundleVersion": "2.1",
    "CFBundleShortVersionString": "2.1",
    "CFBundleInfoDictionaryVersion": "6.0",
    "NSPrincipalClass": "PSListController",
    "PreferenceSpecifiers": specs,
}
with open(os.path.join(B, "Info.plist"), "wb") as f:
    plistlib.dump(info, f)

pl = {"entry": {"bundle": "WeatherLockPrefs", "cell": "PSLinkCell", "label": "锁屏天气"}}
with open(os.path.join(out, "WeatherLock.plist"), "wb") as f:
    plistlib.dump(pl, f)
print("prefs plists written to", out)
