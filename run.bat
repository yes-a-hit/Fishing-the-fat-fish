@echo off
REM Launch the game directly (no editor). Double-click this file.
REM Godot is located by _find_godot.bat; see that file for how.

call "%~dp0_find_godot.bat"
if errorlevel 1 (
    pause
    exit /b 1
)

"%GODOT%" --path "%~dp0."
