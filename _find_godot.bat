@echo off
REM Locate the Godot executable and put its path in %GODOT%.
REM Order: godot_path.txt -> %GODOT% env -> PATH -> common install dirs.

set "GODOT="

REM 1) godot_path.txt next to this file (local, not in version control)
if exist "%~dp0godot_path.txt" (
    set /p GODOT=<"%~dp0godot_path.txt"
    if exist "%GODOT%" exit /b 0
    set "GODOT="
)

REM 2) environment variable
if defined GODOT if exist "%GODOT%" exit /b 0
set "GODOT="

REM 3) PATH
for %%I in (godot.exe godot4.exe) do (
    if not defined GODOT (
        for /f "delims=" %%P in ('where %%I 2^>nul') do set "GODOT=%%P"
    )
)

REM 4) common official distribution layouts
if not defined GODOT (
    for %%D in (
        "%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64.exe"
        "%PROGRAMFILES%\Godot\Godot_v4.7.2-stable_win64.exe"
        "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
        "C:\Godot\Godot_v4.7.2-stable_win64.exe"
    ) do (
        if not defined GODOT if exist %%D set "GODOT=%%~D"
    )
)

if not defined GODOT (
    echo [ERROR] Godot 4.7.2 not found.
    echo.
    echo Pick one:
    echo   1. Put godot_path.txt next to this file, one line: full path to Godot
    echo   2. Set the GODOT environment variable to the Godot executable
    echo   3. Add Godot to PATH
    exit /b 1
)

exit /b 0
