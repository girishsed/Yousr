@echo off
rem Double-click to start the Compane ER demo on Windows. Needs Docker Desktop installed.
cd /d "%~dp0"
echo Starting the Compane ER demo...

docker info >nul 2>&1
if errorlevel 1 (
  echo Opening Docker Desktop...
  start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
  for /l %%i in (1,1,90) do (
    timeout /t 2 /nobreak >nul
    docker info >nul 2>&1 && goto docker_ok
  )
  echo Docker Desktop did not start. Open it yourself, wait until it says running, then try again.
  pause
  exit /b 1
)
:docker_ok

rem If the database design changed since last time, start with a fresh database
for /f %%h in ('powershell -NoProfile -Command "(Get-Content db\*.sql -Raw | Out-String | ForEach-Object { [BitConverter]::ToString((New-Object Security.Cryptography.SHA1Managed).ComputeHash([Text.Encoding]::UTF8.GetBytes($_))) })"') do set VERSION=%%h
set OLD=
if exist .db-version set /p OLD=<.db-version
if defined OLD if not "%OLD%"=="%VERSION%" (
  echo The database design changed, so the demo data is being reset...
  docker compose down -v
)

docker compose up -d --build
if errorlevel 1 (
  echo Something went wrong while starting. See the messages above.
  pause
  exit /b 1
)
echo %VERSION%>.db-version

echo Waiting for the demo to be ready (the first time takes a few minutes)...
for /l %%i in (1,1,150) do (
  curl -sf http://localhost:3000/api/meta >nul 2>&1 && goto ready
  timeout /t 2 /nobreak >nul
)
echo The demo did not answer in time. Open Docker Desktop to see what happened.
pause
exit /b 1

:ready
start "" http://localhost:3000
echo The demo is running at http://localhost:3000
echo You can close this window. To stop the demo, quit Docker Desktop.
pause
