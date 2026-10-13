@echo off
echo ===== 启动 %date% %time% ===== > C:\build\_build_launch.txt
cd /d C:\build\suiya
cmd /c "C:\build\suiya\build_ci.bat"
echo ===== 结束 exit=%errorlevel% %date% %time% ===== >> C:\build\_build_launch.txt
