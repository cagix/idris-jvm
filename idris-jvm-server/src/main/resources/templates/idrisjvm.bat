@echo off

set ERROR_CODE=0
set DEFAULT_JAVA_OPTS="-Xss10m"
setlocal enabledelayedexpansion enableextensions

:init
@REM Decide how to startup depending on the version of windows

@REM -- Win98ME
if NOT "%OS%"=="Windows_NT" goto Win9xArg

@REM set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" @setlocal

@REM -- 4NT shell
if "%eval[2+2]" == "4" goto 4NTArgs

@REM -- Regular WinNT shell
set CMD_LINE_ARGS=%*
goto WinNTGetScriptDir

@REM The 4NT Shell from jp software
:4NTArgs
set CMD_LINE_ARGS=%$
goto WinNTGetScriptDir

:Win9xArg
@REM Slurp the command line arguments.  This loop allows for an unlimited number
@REM of arguments (up to the command line limit, anyway).
set CMD_LINE_ARGS=
:Win9xApp
if %1a==a goto Win9xGetScriptDir
set CMD_LINE_ARGS=%CMD_LINE_ARGS% %1
shift
goto Win9xApp

:Win9xGetScriptDir
set SAVEDIR=%CD%
%0\
cd %0\..
set BASEDIR=%CD%
cd %SAVEDIR%
set SAVE_DIR=
goto repoSetup

:WinNTGetScriptDir
set BASEDIR=%~dp0

if "%JAVACMD%"=="" set JAVACMD=java

for /f %%i in ('where idrisjvm.bat') do set codegen_path=%%i

call :dir_name_from_path bindir !codegen_path!
pushd %bindir%
set BASEDIR=%CD%
popd
goto :end_dir_name_from_path

:dir_name_from_path <resultVar> <pathVar>
(
    set "%~1=%~dp2"
    exit /b
)
:end_dir_name_from_path

@REM Reaching here means variables are defined and arguments have been captured
:endInit

if "%JAVA_OPTS%"=="" set JAVA_OPTS=%DEFAULT_JAVA_OPTS%

%JAVACMD% %JAVA_OPTS% -Dapp.name="${outputName}" -Dapp.home="%BASEDIR%" -Dbasedir="%BASEDIR%" -cp %BASEDIR%\idris-jvm-runtime.jar;%BASEDIR%\${classesDir};%IDRIS_CLASSPATH% %CMD_LINE_ARGS%
if %ERRORLEVEL% NEQ 0 goto error
goto end

:error
if "%OS%"=="Windows_NT" @endlocal
set ERROR_CODE=%ERRORLEVEL%

:end
@REM set local scope for the variables with windows NT shell
if "%OS%"=="Windows_NT" goto endNT

@REM For old DOS remove the set variables from ENV - we assume they were not set
@REM before we started - at least we don't leave any baggage around
set CMD_LINE_ARGS=
goto postExec

:endNT
@REM If error code is set to 1 then the endlocal was done already in :error.
if %ERROR_CODE% EQU 0 @endlocal

:postExec

if "%FORCE_EXIT_ON_ERROR%" == "on" (
  if %ERROR_CODE% NEQ 0 exit %ERROR_CODE%
)

exit /B %ERROR_CODE%
