@echo off
pushd %~dp0
if not exist tools\win32\ (
    tools\win32-tools.exe -otools -y
    call tools\win32-addons\add.bat
)
tools\win32\bin\bash.exe -c 'PATH=$PWD/tools/win32/bin bash extract.sh %*'
pause
