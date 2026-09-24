# ADB Safe Session / Phiên ADB An Toàn

Small **Windows** helper for phone-repair / VoLTE support desks when connecting customer phones over USB/ADB has caused a blue screen (BSOD).

**Honest scope:** this tool **reduces risk** (clean ADB lifecycle + recovery helpers + hardening tips). It does **not** cure all BSODs. Faulty cables, bad USB ports, corrupt or third-party drivers, and hardware faults can still crash Windows.

---

## When to use / Khi nào dùng

| Situation | Action |
|-----------|--------|
| Before plugging a customer phone for ADB/VoLTE work | **Prepare** → plug → **Connect** |
| After a bad connect, stuck ADB, or BSOD + reboot | Unplug phone → **Recover** → then Prepare/Connect only if needed |
| Finished with the phone | **Disconnect** → unplug cable |
| Need a quick reminder of safe habits | **Tips** |

---

## How to run / Cách chạy

### Option A — double-click (recommended)

1. Copy or clone this folder onto the Windows PC: `tools/adb-safe/`
2. Ensure `adb.exe` is on PATH (Android platform-tools) **or** place `adb.exe` next to these scripts.
3. Double-click **`AdbSafe.bat`**

The `.bat` launches PowerShell with `-ExecutionPolicy Bypass` **for this script only** (does not permanently change machine policy).

### Option B — PowerShell

```powershell
cd path\to\tools\adb-safe
powershell -NoProfile -ExecutionPolicy Bypass -File .\AdbSafe.ps1
```

If your org blocks scripts entirely, ask IT to allow this folder, or run the same commands manually from an elevated PowerShell using the flow in the menu.

### Optional one-shot actions

```powershell
.\AdbSafe.ps1 -Action Prepare -NoPause
.\AdbSafe.ps1 -Action Connect -Serial <device-serial> -NoPause
.\AdbSafe.ps1 -Action Disconnect -NoPause
.\AdbSafe.ps1 -Action Recover -NoPause
.\AdbSafe.ps1 -Action Status -NoPause
.\AdbSafe.ps1 -Action Tips -NoPause
.\AdbSafe.ps1 -Action Kill -NoPause
```

### ExecutionPolicy note

You do **not** need to run `Set-ExecutionPolicy RemoteSigned` for the machine if you use `AdbSafe.bat` or `-ExecutionPolicy Bypass -File ...` as above. That bypass is scoped to the launch.

---

## What it does / Việc tool làm

1. **Prepare** — kill stuck `adb` processes, `adb kill-server`, show hardening tips; asks you **not** to plug yet.
2. **Connect** — restart ADB cleanly, wait for devices, **lock to one serial** (`ANDROID_SERIAL`), refuse multi-device ambiguity without a choice.
3. **Status** — show `adb` path, device list, process count.
4. **Disconnect** — disconnect selected device, `kill-server`, clear stuck processes, clear `ANDROID_SERIAL`.
5. **Recover** — after BSOD/bad USB: clear adb, restart server; if elevated Admin, attempt safe enable/disable of a few USB hubs; otherwise print Device Manager steps.
6. **Tips / Kill** — hardening notes or force-kill adb only.

CLI messages are short **Vietnamese + English** so a support tech can move quickly.

---

## What it does **not** do / Việc tool **không** làm

- Does **not** guarantee no BSOD.
- Does **not** install, download, or patch USB/ADB drivers.
- Does **not** flash phones, change VoLTE configs, or replace your VoLTE tooling.
- Does **not** require or install any “driver booster” / third-party USB packs (those often increase risk).
- USB hub reset needs **Administrator**; without Admin it only prints manual recovery steps.

---

## Safety notes / An toàn

- Prefer **one labeled known-good USB port** (often a rear USB 2.0 port) and a short data cable.
- Use **Google USB Driver** or the phone OEM driver only — avoid random driver update utilities.
- Optional Windows setting: *System Properties → Hardware → Device Installation Settings → No* to limit automatic driver installs.
- If BSOD repeats on the **same** port after recovery, treat it as hardware/driver isolation: swap port, cable, or PC before blaming ADB alone.
- Always **Disconnect** before unplugging when possible.

---

## Layout

```
tools/adb-safe/
  AdbSafe.ps1   # main tool
  AdbSafe.bat   # Windows launcher
  README.md     # this file
```
