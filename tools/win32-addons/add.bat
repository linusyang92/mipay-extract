@echo off
pushd %~dp0
copy net.dll ..\win32\jre\bin\
copy nio.dll ..\win32\jre\bin\
copy tzdb.dat ..\win32\jre\lib\
copy tzmappings ..\win32\jre\lib\
copy jce.jar ..\win32\jre\lib\
copy find.exe ..\win32\bin\
popd
