@echo off
setlocal

set SCRIPT_DIR=%~dp0
set MATLAB_BIN=matlab

echo Starting portable MATLAB+COMSOL batch run...
echo Package root: %SCRIPT_DIR%

%MATLAB_BIN% -batch "run(fullfile('%SCRIPT_DIR%','portable_runner','portable_run_batch.m'))"

endlocal
