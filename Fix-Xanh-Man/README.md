# Fix Xanh Màn Khởi Động lại — ADB Safe + TG82

Công cụ Windows hỗ trợ bàn VoLTE / sửa máy khi dùng **USB Redirector TG82 Auto + ADB**.

**Bằng chứng vận hành:** PC xanh màn (BSOD) + reboot **ngay** khi connect ADB qua TG82 Auto. Tool **không** bảo bỏ TG82 (vẫn cần remote USB) — chỉ bắt **đúng thứ tự**.

**Phạm vi trung thực:** giảm rủi ro theo lifecycle. **Không** chữa 100% BSOD (cáp, cổng, driver, phần cứng vẫn có thể crash).

---

## Thư mục đích trên máy Windows

```
D:\TOOL\Fix Xanh Màn Khởi Động lại\
```

Cài nhanh bằng script (tạo thư mục + copy file + mở Explorer):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CaiDat-Ve-O-D.ps1
```

Hoặc one-liner tải từ nhánh PR (chạy trên PC Windows có mạng):

```powershell
$u='https://raw.githubusercontent.com/mobjle2/TG82-VoLTE-Release/cursor/adb-safe-bsod-tool-e134/Fix-Xanh-Man/CaiDat-Ve-O-D.ps1'; $f="$env:TEMP\CaiDat-Ve-O-D.ps1"; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; curl.exe -fsSL $u -o $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

---

## Thứ tự bắt buộc (TG82 Auto)

```
kill ADB  →  TG82 Share  →  Connect (ADB)  →  làm việc
         →  Disconnect / kill ADB  →  TG82 Unshare
```

| Bước | Làm gì |
|------|--------|
| 1 | Chạy tool → menu **8** Prepare TG82 (ADB tắt) |
| 2 | TG82 Auto → **Share** đúng **1** máy → chờ 3–5 giây |
| 3 | Menu **2** Connect → chốt 1 serial → làm VoLTE |
| 4 | Xong: Menu **9** Disconnect TG82 → ADB tắt |
| 5 | TG82 Auto → **Unshare** (rồi mới rút dây phía khách nếu cần) |

Sau BSOD: menu **5 Recover** → Unshare session treo → chỉ Share lại sau bước 8.

---

## Cách chạy

Cần `adb.exe` trong PATH (hoặc đặt cạnh script trong `adb-safe\`).

**Khuyến nghị:** double-click **`Chay-AdbSafe.bat`** ở thư mục gốc dự án.

Hoặc:

```bat
Chay-AdbSafe.bat
```

```powershell
cd adb-safe
powershell -NoProfile -ExecutionPolicy Bypass -File .\AdbSafe.ps1
```

One-shot reconnect:

```powershell
cd adb-safe
.\AdbSafe.ps1 -Action PrepareTg82 -NoPause
# → Share trong TG82, chờ ổn định
.\AdbSafe.ps1 -Action Connect -NoPause
# …làm việc…
.\AdbSafe.ps1 -Action DisconnectTg82 -NoPause
# → Unshare trong TG82
```

`.bat` / `-ExecutionPolicy Bypass` chỉ áp dụng lần chạy đó — **không** đổi policy máy.

---

## Cấu trúc dự án

```
Fix-Xanh-Man/                    ← root = nội dung D:\TOOL\Fix Xanh Màn Khởi Động lại\
  README.md                      ← tài liệu tiếng Việt (file này)
  CaiDat-Ve-O-D.ps1              ← tạo D:\TOOL\… và copy/tải toàn bộ file
  Chay-AdbSafe.bat               ← launcher nhanh
  adb-safe\
    AdbSafe.ps1                  ← tool chính (VI/EN)
    AdbSafe.bat                  ← bypass ExecutionPolicy
    README.md                    ← ghi chú kỹ thuật ngắn
```

Trong repo GitHub: thư mục `Fix-Xanh-Man/`. Bản cũ `tools/adb-safe/` vẫn giữ để tương thích; **nguồn dùng hàng ngày** là gói này.

---

## Tool làm gì / không làm gì

**Làm:** Prepare / Prepare TG82, Connect 1 thiết bị, Disconnect / Disconnect TG82, Recover sau BSOD, checklist thứ tự an toàn.

**Không:** bảo hành hết BSOD; cài/cập nhật TG82; tự bấm Share/Unshare trong UI TG82; thay tool VoLTE.

Giảm rủi ro — **không** bảo hành hết BSOD.
