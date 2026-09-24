# Fix Xanh Màn — ADB + TG82

Giảm rủi ro xanh màn khi dùng **TG82 Auto + ADB**. **Không** chữa 100% BSOD.

**Thư mục trên Windows:** `D:\TOOL\Fix Xanh Màn Khởi Động lại\`

## Chạy

Double-click **`Fix.bat`**

Script sẽ: **tắt ADB sạch** → in 2 bước Share / Unshare.

```
Fix.bat  →  TG82 Share  →  làm việc  →  Fix.bat  →  TG82 Unshare
```

Sau xanh màn (một lần):

```bat
Fix.bat -SauXanhMan
```

## Cài về ổ D:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CaiDat-Ve-O-D.ps1
```

One-liner:

```powershell
$u='https://raw.githubusercontent.com/mobjle2/TG82-VoLTE-Release/cursor/adb-safe-bsod-tool-e134/Fix-Xanh-Man/CaiDat-Ve-O-D.ps1'; $f="$env:TEMP\CaiDat-Ve-O-D.ps1"; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; curl.exe -fsSL $u -o $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

## File

```
Fix.bat              ← double-click đây
Fix.ps1              ← logic tắt ADB
CaiDat-Ve-O-D.ps1    ← cài vào D:\TOOL\...
README.md
```
