@echo off
chcp 65001 >nul
set "MEDIA_APP=%~dp0welcome_uart_gui.py"

where py >nul 2>nul
if not errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath 'py' -ArgumentList '-3','%MEDIA_APP%' -Verb RunAs"
    exit /b
)

where python >nul 2>nul
if not errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath 'python' -ArgumentList '%MEDIA_APP%' -Verb RunAs"
    exit /b
)

echo 未找到 Python 3。请先安装 Python 3，并执行：pip install pyserial pillow
pause
