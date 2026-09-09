@echo off
setlocal
set "INSTALLER_URL=https://github.com/dixithsnaik/fiberapi/releases/latest/download/install.ps1"
set "INSTALLER_FILE=%TEMP%\fiber-install-%RANDOM%.ps1"

echo Downloading FiberAPI installer...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -Uri '%INSTALLER_URL%' -OutFile '%INSTALLER_FILE%'"
if errorlevel 1 goto :error

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER_FILE%"
set "RESULT=%ERRORLEVEL%"
del /q "%INSTALLER_FILE%" >nul 2>&1
if not "%RESULT%"=="0" goto :error

echo.
echo FiberAPI CLI installed successfully.
echo Opening a new PowerShell window with the updated PATH...
start "FiberAPI" powershell.exe -NoLogo -NoExit -Command "$env:Path=[Environment]::GetEnvironmentVariable('Path','User')+';'+[Environment]::GetEnvironmentVariable('Path','Machine'); fiber help"
pause
exit /b 0

:error
echo.
echo FiberAPI installation failed.
pause
exit /b 1
