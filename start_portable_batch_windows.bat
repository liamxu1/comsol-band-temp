@echo off
setlocal

set SCRIPT_DIR=%~dp0
set MATLAB_BIN=matlab

echo Legacy compatibility entry for portable MATLAB+COMSOL batch run.
echo Package root: %SCRIPT_DIR%
echo.
echo Recommended workflow:
echo   1. Open COMSOL with MATLAB manually.
echo   2. In that session, run:
echo      run(fullfile('%SCRIPT_DIR%','portable_runner','portable_run_batch.m'))
echo.
echo This .bat remains available as a compatibility path and launches a plain MATLAB host session.

"%MATLAB_BIN%" -batch "run(fullfile('%SCRIPT_DIR%','portable_runner','portable_run_batch.m'))"

endlocal
