锁屏天气 AxsWeatherLock v2.2（带设置界面 + 诊断日志）
=========================================

文件
 src/AxsWeatherLock.m       SpringBoard 主体 v2.3（挂锁屏视图）
 src/WeatherLockPrefs.m     设置面板占位二进制（5 行，界面由 plist 生成）
 src/axs_weather            命令行配置工具
 tools/make_prefs.py        生成设置项 plist（workflow 会自动拉，可不传）
 .github/workflows/weather.yml  GitHub 编译脚本

编译
 仓库里放：src/AxsWeatherLock.m、src/WeatherLockPrefs.m（或都放根目录）
 以及 .github/workflows/weather.yml
 Actions → build-weatherlock → Run workflow
 产物 weatherlock-arm64e.zip 内含：
   AxsWeatherLock.dylib
   WeatherLockPrefs.bundle（Info.plist + 二进制）
   WeatherLock.plist（设置里的入口）

设置界面
 设置 App → 锁屏天气（在「设置」列表里，需要 PreferenceLoader）
 可调：token / 城市 / 经纬度
       主行字号 / 彩虹跨度 / 亮度 / 纯色 hex
       水平偏移 / 距顶 / 宽度 / 高度 / 内边距 / 行距 / 圆角
       背景跟随天气 / 不透明度 / 纯色背景
       未来 3 小时开关 / 今日高低与日出日落开关
 改完回桌面，锁屏 2 秒内生效（无需重启）

命令行（一样有效，优先级：设置面板 > config.txt）
 axs_weather show
 axs_weather token 你的token
 axs_weather size 16 / color #FFB300 / bg dark / alpha .6
 axs_weather pos 0 90 / width 340 / height 120
 axs_weather refresh

回退
 dpkg -r com.axs.weatherlock
 killall SpringBoard
