// WeatherLockPrefs.m — 设置面板占位二进制
// 界面完全由 Info.plist 里的 PreferenceSpecifiers + Preferences.framework 的
// PSListController 提供，这里只要有能被 dlopen 的可执行体即可。
#import <Foundation/Foundation.h>
__attribute__((constructor)) static void wlprefs_init(void) { }
