// WeatherLockPrefs.m — 设置面板控制器（Preferences.framework 的 PSListController 子类）
// 界面内容全部来自 WeatherLockRoot.plist；读写走 defaults = com.axs.weatherlock
// 不 import Preferences 头文件，符号用 dynamic_lookup 在运行期解析
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface WeatherLockRootListController : PSListController
@end

@implementation WeatherLockRootListController

- (NSArray *)specifiers {
    static NSArray *specs = nil;
    if (!specs) {
        specs = [self loadSpecifiersFromPlistName:@"WeatherLockRoot" target:self];
    }
    return specs;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏天气";
}

@end
