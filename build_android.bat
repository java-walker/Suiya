@echo off
REM ============================================================
REM  岁忆 · Android 构建脚本
REM  用法：双击运行，或在 cmd 中执行 build_android.bat
REM ============================================================

echo.
echo ============================================
echo   岁忆 · Android APK 构建
echo ============================================
echo.

REM ---- 1. 设置环境变量 ----
set FLUTTER_SDK=C:\Users\XX\.workbuddy\binaries\flutter_sdk
set JAVA_HOME=C:\Users\XX\.workbuddy\binaries\jdk\17
set ANDROID_HOME=C:\Users\XX\.workbuddy\binaries\android-sdk
set GRADLE_USER_HOME=C:\Users\XX\.workbuddy\binaries\gradle-home

set PATH=%FLUTTER_SDK%\bin;%JAVA_HOME%\bin;%PATH%

REM ---- 2. 国内镜像（加速依赖下载）----
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

REM ---- 3. 关闭遥测（避免多余进程）----
set FLUTTER_SUPPRESS_ANALYTICS=true
set DART_CLI_TELEMETRY_DISABLED=1

REM ---- 4. 进入项目 ----
cd /d "%~dp0"
echo [1/4] 当前目录：%CD%
echo.

REM ---- 5. 环境自检 ----
echo [2/4] 检查环境...
where flutter >nul 2>&1
if errorlevel 1 (
    echo [错误] 找不到 flutter，请检查 PATH 设置
    pause
    exit /b 1
)
where java >nul 2>&1
if errorlevel 1 (
    echo [错误] 找不到 java，请检查 JAVA_HOME
    pause
    exit /b 1
)
echo       flutter: OK
echo       java:    OK
echo.

REM ---- 6. 清理旧产物 ----
echo [3/4] 清理旧构建...
if exist build\app\outputs\flutter-apk rmdir /s /q build\app\outputs\flutter-apk 2>nul
echo       完成
echo.

REM ---- 7. 构建 ----
echo [4/4] 开始构建 APK（首次约需 5-15 分钟）...
echo.
flutter build apk --debug
if errorlevel 1 (
    echo.
    echo [构建失败] 请查看上方错误信息
    pause
    exit /b 1
)

echo.
echo ============================================
echo   构建成功！
echo ============================================
echo.
echo APK 位置：
echo   %CD%\build\app\outputs\flutter-apk\app-debug.apk
echo.
echo 安装到手机：adb install build\app\outputs\flutter-apk\app-debug.apk
echo.
pause
