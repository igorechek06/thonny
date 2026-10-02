@echo off

set BUILDDIR=build
@rem Following can be overridden with environment variables (eg. on CI)
if "%PYTHON_DIR%"=="" set "PYTHON_DIR=C:\Program Files\Python314"
if "%THONNY_PACKAGES%"=="" set "THONNY_PACKAGES=thonny"

del %BUILDDIR% /Q
rmdir %BUILDDIR% /S /Q
mkdir %BUILDDIR%

@echo ............... COPYING PYTHON ...................................
xcopy "%PYTHON_DIR%\*" %BUILDDIR% /S /E /K>NUL
@echo ............... COPYING OTHER STUFF ...................................
copy ThonnyRunner314\x64\Release\thonny.exe %BUILDDIR% /Y
copy thonny_python.ini %BUILDDIR%

@echo ............... INSTALLING DEPS ...................................

%BUILDDIR%\python -s -m pip install --no-warn-script-location --no-cache-dir wheel
if errorlevel 1 exit /b 1

%BUILDDIR%\python -s -m pip install --no-warn-script-location --no-cache-dir --no-binary mypy -r ..\requirements-regular-bundle.txt
if errorlevel 1 exit /b 1

@echo ............... INSTALLING THONNY ...................................
%BUILDDIR%\python -s -m pip install --no-warn-script-location --pre --no-cache-dir %THONNY_PACKAGES%
if errorlevel 1 exit /b 1
@rem %BUILDDIR%\python -s -m pip install --no-warn-script-location ..\..\dist\thonny-4.2.0.dev1-py3-none-any.whl

@echo ............... CLEANING PYTHON ............................
@rem move following 3 files to avoid confusion (user may think they're Thonny license etc.)
move %BUILDDIR%\LICENSE.txt %BUILDDIR%\PYTHON_LICENSE.txt
move %BUILDDIR%\README.txt %BUILDDIR%\PYTHON_README.txt
move %BUILDDIR%\NEWS.txt %BUILDDIR%\PYTHON_NEWS.txt

del /S "%BUILDDIR%\*.pyc">NUL
@rem del /S "%BUILDDIR%\*.lib">NUL
del /S "%BUILDDIR%\tcl\*.lib">NUL
del /S "%BUILDDIR%\*.a">NUL
del /S "%BUILDDIR%\*.chm">NUL

rmdir %BUILDDIR%\Doc /S /Q>NUL
@rem rmdir %BUILDDIR%\include /S /Q>NUL
@rem rmdir %BUILDDIR%\libs /S /Q>NUL
rmdir %BUILDDIR%\Tools /S /Q>NUL
del "%BUILDDIR%\Scripts\*" /Q>NUL

copy .\pip.bat "%BUILDDIR%\Scripts\pip.bat"
copy .\pip.bat "%BUILDDIR%\Scripts\pip3.bat"
copy .\pip.bat "%BUILDDIR%\Scripts\pip3.14.bat"

rmdir %BUILDDIR%\lib\test /S /Q>NUL

del %BUILDDIR%\tcl\*.sh /Q>NUL
del %BUILDDIR%\tcl\tcl8.6\clock.tcl>NUL
del %BUILDDIR%\tcl\tcl8.6\safe.tcl>NUL
rmdir %BUILDDIR%\tcl\tix8.4.3\demos /S /Q>NUL

rmdir %BUILDDIR%\tcl\tk8.6\demos /S /Q>NUL
rmdir %BUILDDIR%\tcl\tk8.6\msgs /S /Q>NUL

rmdir %BUILDDIR%\tcl\tcl8.6\opt0.4 /S /Q>NUL
rmdir %BUILDDIR%\tcl\tcl8.6\msgs /S /Q>NUL
rmdir %BUILDDIR%\tcl\tcl8.6\tzdata /S /Q>NUL

rmdir %BUILDDIR%\lib\site-packages\pylint\test /S /Q>NUL
rmdir %BUILDDIR%\lib\site-packages\mypy\test /S /Q>NUL

@rem Not needed for running the language server
rmdir %BUILDDIR%\lib\site-packages\nodejs_wheel\lib /S /Q>NUL
del %BUILDDIR%\lib\site-packages\basedpyright\dist\*.js.map>NUL
del %BUILDDIR%\lib\site-packages\basedpyright\dist\pyright.js>NUL


@echo ............... ADDING LICENSES ...................................
copy ..\..\LICENSE.txt %BUILDDIR% /Y>NUL
mkdir %BUILDDIR%\licenses
xcopy ..\..\licenses\* %BUILDDIR%\licenses /S /E /K>NUL

@echo ............... ADDING OTHER STUFF ...................................
copy ..\..\CHANGELOG.rst %BUILDDIR% /Y>NUL
copy ..\..\CREDITS.rst %BUILDDIR% /Y>NUL
copy ..\..\README.rst %BUILDDIR% /Y>NUL


@echo ............... CREATING INSTALLER ..........................
set /p VERSION=<%BUILDDIR%\Lib\site-packages\thonny\VERSION
"C:\Program Files (x86)\Inno Setup 6\iscc" /dInstallerPrefix=thonny /dAppVer=%VERSION% /dArch=x64 /dSupportedArchitectures="x64compatible arm64" /dSourceFolder=build %ISCC_ARGS% inno_setup.iss > installer_building.log
if errorlevel 1 (
    type installer_building.log
    exit /b 1
)

@echo ............... CREATING ZIP ..........................
SET PATH=%PATH%;C:\Program Files\7-Zip
copy ..\portable_thonny.ini %BUILDDIR%
cd %BUILDDIR%
7z a -tzip ..\dist\thonny-%VERSION%-windows-portable-x64.zip *
del portable_thonny.ini
cd ..

