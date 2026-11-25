@echo off
echo ========================================================
echo   OnePlus Pad Pro (caihong) - Switch to Slot B (Ubuntu)
echo ========================================================
echo.
fastboot devices
if %errorlevel% neq 0 (
    echo Error: No device detected in Fastboot mode!
    pause
    exit /b 1
)

echo Setting active slot to B...
fastboot --set-active=b
echo Rebooting into Ubuntu 24.04...
fastboot reboot
echo Done!
pause
