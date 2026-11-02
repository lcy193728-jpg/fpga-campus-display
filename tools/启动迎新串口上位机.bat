@echo off
chcp 65001 >nul
set "UART_APP=%~dp0welcome_uart_gui.py"

where py >nul 2>nul
if not errorlevel 1 (
    py -3 "%UART_APP%"
    if errorlevel 1 pause
    exit /b
)

where python >nul 2>nul
if not errorlevel 1 (
    python "%UART_APP%"
    if errorlevel 1 pause
    exit /b
)

if exist "D:\python3-13\python.exe" (
    "D:\python3-13\python.exe" "%UART_APP%"
    if errorlevel 1 pause
    exit /b
)

echo 未找到 Python 3。请先安装 Python 3，并执行：pip install pyserial pillow
pause
