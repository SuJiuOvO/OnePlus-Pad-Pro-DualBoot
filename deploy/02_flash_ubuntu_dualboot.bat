@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   OnePlus Pad Pro (caihong) - Flash Ubuntu 24.04 Dual Boot
echo ========================================================
echo.
echo [!] Requirements:
echo   1. Bootloader is UNLOCKED
echo   2. Device is connected in Fastboot mode
echo   3. A partition named 'linux' exists in GPT (or will be flashed)
echo   4. Target slot for Linux is Slot B (Slot A remains original Android)
echo.
pause

echo.
echo [1/5] Checking fastboot connection...
fastboot devices
if %errorlevel% neq 0 (
    echo Error: Fastboot device not found. Please connect your tablet in Fastboot mode!
    pause
    exit /b 1
)

echo.
echo [2/5] Erasing DTBO for Slot B (Mainline DTB is inside boot image)...
fastboot erase dtbo_b

echo.
echo [3/5] Flashing Ubuntu 24.04 Mainline Kernel (boot_b)...
fastboot flash boot_b boot\caihong-boot-linux.img
if %errorlevel% neq 0 (
    echo Error: Failed to flash boot_b!
    pause
    exit /b 1
)

echo.
echo [4/5] Flashing Ubuntu 24.04 ARM64 RootFS to partition 'linux'...
fastboot flash linux rootfs\caihong-ubuntu24-rootfs.ext4.sparse.img
if %errorlevel% neq 0 (
    echo Error: Failed to flash linux partition!
    echo Please make sure you have created the partition with label 'linux'.
    pause
    exit /b 1
)

echo.
echo [5/5] Activating Slot B...
fastboot --set-active=b

echo.
echo ========================================================
echo   Flashing complete! Rebooting into Ubuntu 24.04...
echo   Default user: ubuntu (password: ubuntu)
echo   Root user:    root   (password: root)
echo   To switch back to Android at any time, run: switch_to_android.bat
echo ========================================================
fastboot reboot
pause
