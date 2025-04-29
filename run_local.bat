@echo off
echo Terraform Trek Launcher
echo.
echo If you see an error, please follow these steps:
echo 1. Download and install LÖVE from https://love2d.org/
echo 2. After installation, edit this file and replace the path below with your LÖVE installation path
echo 3. Common installation paths are:
echo    - C:\Program Files\LOVE\love.exe
echo    - C:\Program Files (x86)\LOVE\love.exe
echo.
echo Current path being used:
set LOVE_PATH="C:\Program Files\LOVE\love.exe"
echo %LOVE_PATH%
echo.
echo If this is not correct, please edit this file and update the LOVE_PATH variable.
echo.
echo Press any key to try running the game...
pause > nul

%LOVE_PATH% .
pause 