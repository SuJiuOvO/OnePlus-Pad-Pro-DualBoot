@echo off
echo ========================================================
echo   OnePlus Pad Pro (caihong) - Switch to Slot A (Android)
echo ========================================================
echo.
fastboot devices
if %errorlevel% neq 0 (
    echo Error: No device detected in Fastboot mode!
    pause
    exit /b 1
)

echo Setting active slot to A...
fastboot --set-active=a
echo Rebooting into Android...
fastboot reboot
echo Done!
pause
