# ADB Safe Session / Phiên ADB An Toàn

> **Gói đầy đủ (khuyến nghị):** thư mục repo [`Fix-Xanh-Man/`](../../Fix-Xanh-Man/)  
> **Cài trên Windows tới:** `D:\TOOL\Fix Xanh Màn Khởi Động lại`  
> Script: [`Fix-Xanh-Man/CaiDat-Ve-O-D.ps1`](../../Fix-Xanh-Man/CaiDat-Ve-O-D.ps1)

Thư mục `tools/adb-safe/` giữ bản tool gốc (tương thích). Dùng hàng ngày hãy cài gói `Fix-Xanh-Man`.

---

Small **Windows** helper for phone-repair / VoLTE desks. Covers **local USB** and the high-risk path **USB Redirector TG82 Auto + ADB**.

**Operator evidence:** BSOD + reboot happened **immediately** when connecting ADB through **USB Redirector TG82 Auto**. This tool keeps TG82 in the workflow — it does **not** tell you to abandon remote USB.

**Honest scope:** reduces risk via ordered lifecycle. Does **not** cure all BSODs (hardware, cables, ports, filter drivers can still crash Windows).

---

## Safe order (TG82 Auto) — memorize this

```
kill ADB  →  TG82 Share  →  Connect (ADB)  →  work
         →  Disconnect / kill ADB  →  TG82 Unshare
```

| Step | Menu | What you do |
|------|------|-------------|
| 1 | **8 Prepare TG82** | Kill stuck `adb` + `kill-server` |
| 2 | TG82 Auto UI | **Share** / Attach **one** customer phone only |
| 3 | Wait 3–5s | Device stable; do not start VoLTE yet |
| 4 | **2 Connect** | `start-server`, lock one serial, then work |
| 5 | Finish work | Close VoLTE / stop adb commands |
| 6 | **9 Disconnect TG82** | Kill ADB again |
| 7 | TG82 Auto UI | **Unshare** / Release — then unplug customer-side if needed |

After BSOD: **5 Recover** → Unshare any stuck session → only Share again after step 1.

---

## How to run (NOW)

### Cài gói đầy đủ lên ổ D: (khuyến nghị)

```powershell
# Tu thu muc Fix-Xanh-Man da clone:
powershell -NoProfile -ExecutionPolicy Bypass -File .\CaiDat-Ve-O-D.ps1
```

One-liner (PC Windows có mạng):

```powershell
$u='https://raw.githubusercontent.com/mobjle2/TG82-VoLTE-Release/cursor/adb-safe-bsod-tool-e134/Fix-Xanh-Man/CaiDat-Ve-O-D.ps1'; $f="$env:TEMP\CaiDat-Ve-O-D.ps1"; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; curl.exe -fsSL $u -o $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

Sau đó: `D:\TOOL\Fix Xanh Màn Khởi Động lại\Chay-AdbSafe.bat`

### Chỉ dùng thư mục này

1. Copy `tools/adb-safe/` to the Windows PC (or pull this PR branch).
2. Need `adb.exe` on PATH (or next to the scripts).
3. Double-click **`AdbSafe.bat`**

```powershell
cd tools\adb-safe
powershell -NoProfile -ExecutionPolicy Bypass -File .\AdbSafe.ps1
```

One-shot for reconnect:

```powershell
.\AdbSafe.ps1 -Action PrepareTg82 -NoPause
# → Share in TG82 Auto (one phone), wait 3–5s
.\AdbSafe.ps1 -Action Connect -NoPause
# → work…
.\AdbSafe.ps1 -Action DisconnectTg82 -NoPause
# → Unshare in TG82 Auto
```

`.bat` / `-ExecutionPolicy Bypass` is **launch-scoped only** (does not change machine policy).

---

## What it does

- **Prepare / Prepare TG82** — stop ADB before plug or before Share  
- **Connect** — clean start-server, **one** device (`ANDROID_SERIAL`)  
- **Disconnect / Disconnect TG82** — kill ADB before unplug / before Unshare  
- **Recover** — clear adb after BSOD; optional Admin USB hub refresh; TG82 Unshare checklist  
- **Checklist / Tips** — print the safe order + modest public notes on USB-redirect + BSOD class of bugs  
- Best-effort detection of TG82 / USB Redirector process or `tusbd`/`dpnptls` services  

## What it does **not** do

- Guarantee no BSOD  
- Install/update TG82 or USB drivers  
- Automate the TG82 Share/Unshare UI (you click that)  
- Replace VoLTE tooling  

---

## Public context (modest)

- USB Redirector–class products use **kernel** USB/virtual-bus drivers; vendor changelogs for IncentivesPro USB Redirector repeatedly list **BSOD fixes** around stub/unplug/connected state ([news](https://www.incentivespro.com/news.html)). That is **general** redirect risk, not a proven dump for this operator’s PC.  
- USB-over-IP + Android ADB has public BSOD reports (e.g. [usbipd-win #461](https://github.com/dorssel/usbipd-win/issues/461)). Same **risk class**, different product.  
- We do **not** have this operator’s minidump; if BSOD repeats, capture STOP code / `MODULE_NAME` via WinDbg `!analyze -v`.

---

## Layout

```
Fix-Xanh-Man/                 ← gói standalone (home Windows)
  CaiDat-Ve-O-D.ps1
  Chay-AdbSafe.bat
  README.md
  adb-safe\
    AdbSafe.ps1
    AdbSafe.bat
    README.md

tools/adb-safe/               ← bản giữ tương thích
  AdbSafe.ps1
  AdbSafe.bat
  README.md
```
