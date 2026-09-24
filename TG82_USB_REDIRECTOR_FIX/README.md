# TG82_USB_REDIRECTOR_FIX

Tool **riêng** — tối ưu USB Redirector Technician Edition + ADB an toàn (giảm rủi ro BSOD).  
**Không** đụng tool VoLTE chính. **Không** dùng `USB1.9.7_Auto_Connect_Online_EFT.exe`. **Không** tự cài/đổi driver.

## Cài đặt

Thư mục đích:

```
D:\TOOL\TG82_USB_REDIRECTOR_FIX
```

Chạy `Install-To-D.ps1` (copy local hoặc tải từ nhánh PR).

## Cách chạy

Double-click:

```
D:\TOOL\TG82_USB_REDIRECTOR_FIX\TG82_USB_REDIRECTOR_FIX.bat
```

Cửa sổ nhỏ có 2 nút:

1. **AUTO FIX BSOD ADB** — DETECT → SAFE LOCK → ADB CLEAN → USB RESET → MODE GUARD → VERIFY
2. **COLLECT BSOD LOG** — zip minidump / Event Log / log USB Redirector / trạng thái adb+service

## Báo cáo (cuối AUTO FIX)

```
USB_REDIRECTOR_FOUND =
ADB_CONFLICT =
AUTO_REBIND_DISABLED =
ADB_RESET =
USB_SERVICE_RESET =
SAFE_RECONNECT =
MODE_TRANSITION_GUARD =
FINAL_ADB =
BSOD_RISK_REDUCED =
```

Giá trị: `PASS` / `FAIL` / `SKIP` (bỏ qua nếu thiếu TG82 / không đủ quyền admin).

Log chi tiết: thư mục `logs\`.

## Lưu ý

Giảm rủi ro BSOD — **không** bảo hành hết xanh màn.
