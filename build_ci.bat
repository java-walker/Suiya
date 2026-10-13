@echo off
echo ===== build start %date% %time% ===== > C:\build\_build_launch.txt
set LOG=C:\build\suiya\build_ci.log
echo ===== SuiYi CI build start %date% %time% ===== > "%LOG%"

set FLUTTER_SDK=C:\Users\XX\.workbuddy\binaries\flutter_sdk
set JAVA_HOME=C:\Users\XX\.workbuddy\binaries\jdk\17
set ANDROID_HOME=C:\Users\XX\.workbuddy\binaries\android-sdk
set GRADLE_USER_HOME=C:\Users\XX\.workbuddy\binaries\gradle-home
set PATH=%FLUTTER_SDK%\bin;%JAVA_HOME%\bin;%PATH%

set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_SUPPRESS_ANALYTICS=true
set DART_CLI_TELEMETRY_DISABLED=1
set http_proxy=
set https_proxy=
set HTTP_PROXY=
set HTTPS_PROXY=
set all_proxy=
set ALL_PROXY=

cd /d C:\build\suiya
echo [INFO] flutter --version >> "%LOG%"
call flutter --version >> "%LOG%" 2>&1
echo [INFO] flutter build apk --release >> "%LOG%"
call flutter build apk --release >> "%LOG%" 2>&1
echo ===== build end exit=%errorlevel% %date% %time% ===== >> "%LOG%"
echo ===== done %date% %time% ===== >> C:\build\_build_launch.txt
