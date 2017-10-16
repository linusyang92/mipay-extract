@echo off
pushd %~dp0
if not exist tools\win32\ (
    tools\win32-tools.exe -otools -y
)
tools\win32\bin\bash.exe -c 'PATH=$PWD/tools/win32/bin bash deploy.sh %*'
pause
