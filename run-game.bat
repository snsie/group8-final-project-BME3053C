@echo off
REM Run Microbe Mayhem (LÖVE) and keep the console open to show errors
SET LOVE_EXE="C:\Program Files\LOVE\love.exe"
IF NOT EXIST %LOVE_EXE% (
  echo Could not find LÖVE at %LOVE_EXE%
  echo If you installed LÖVE in a different location, edit this file to set the correct path.
  pause
  exit /b 1
)

REM Run LÖVE pointing at this folder (the script's directory)
pushd "%~dp0"
echo Running LÖVE from %LOVE_EXE% on %CD%
%LOVE_EXE% "%CD%"
echo.
echo LÖVE exited with code %ERRORLEVEL%.
echo If there are error messages above, copy them and paste here for help.
pause
popd
