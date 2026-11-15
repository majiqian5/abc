//
//  AxsWeatherLock.m — 锁屏天气（彩云 API v2.5）
//  注入 SpringBoard；配置走 /var/jb/var/mobile/Library/WeatherLock/config.txt
//  彩虹渐变逐字着色 / 字号·位置·背景可调 / 实时预报 + 小时预报 + 降水提醒
//
//  v2 修正：
//   1) token 支持"自己填"占位，未填时锁屏显示提示而不是空白
//   2) color 支持 rainbow / white / #RRGGBB（旧版只认数字，填字符串无效）
//   3) bg 支持 weather / dark / none / #RRGGBB（旧版只认数字）
//   4) 文字改用 UIKit 逐字绘制（旧版 CTLine 在翻转坐标系下有上下颠倒风险）
//   5) 增加 AQI、今日最高最低、日出日落、超宽自动换行
//  v2.4：钩子改为只在目标类自己实现时替换，否则 class_addMethod（避免污染整个继承链）
//  v2.3：不再依赖 isLocked —— 直接 hook 锁屏控制器，把视图贴到锁屏 view 上
//  v2.2：加诊断日志 /var/tmp/axswl.log；场景查找三重兜底（防止取不到 windowScene 导致窗口不创建）
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <objc/message.h>
#include <math.h>

static NSString *const kCfgPath  = @"/var/jb/var/mobile/Library/WeatherLock/config.txt";
static NSString *const kCachePath = @"/var/jb/var/mobile/Library/WeatherLock/cache.json";

// 诊断日志：/var/tmp/axswl.log（写不进去就退到 Preferences 目录）
static void wlLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.0f] %@\n", CFAbsoluteTimeGetCurrent(), msg];
    NSArray *paths = @[@"/var/tmp/axswl.log",
                       @"/var/jb/var/mobile/Library/Preferences/axswl.log",
                       @"/var/mobile/Library/Preferences/axswl.log"];
    for (NSString *p in paths) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; return; }
    }
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] createFileAtPath:p contents:[line dataUsingEncoding:NSUTF8StringEncoding] attributes:nil]) return;
    }
}

// ---------------------------------------------------------------- 配置
static NSMutableDictionary *gCfg = nil;

static NSString *cfgStr(NSString *k, NSString *def) {
    id v = gCfg[k];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return def;
}
static double cfgNum(NSString *k, double def) {
    id v = gCfg[k];
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    if ([v isKindOfClass:[NSString class]]) return [v doubleValue];
    return def;
}

// token 占位判断：留空 / 中文占位 / PASTE 都会被视为"还没填"
static BOOL tokenReady(void) {
    NSString *t = cfgStr(@"token", @"");
    if (t.length < 20) return NO;
    if ([t rangeOfString:@"填"].location != NSNotFound) return NO;
    if ([t rangeOfString:@"PASTE"].location != NSNotFound) return NO;
    if ([t rangeOfString:@"TOKEN"].location != NSNotFound) return NO;
    return YES;
}

static UIColor *colorFromHex(NSString *hex, UIColor *def) {
    if (![hex isKindOfClass:[NSString class]] || !hex.length) return def;
    NSString *s = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (s.length != 6) return def;
    unsigned int v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    if (![sc scanHexInt:&v]) return def;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0 alpha:1];
}

// 设置面板写入的偏好（/var/jb/var/mobile/Library/Preferences/com.axs.weatherlock.plist）
static void mergePrefs(NSMutableDictionary *d) {
    NSDictionary *pd = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/jb/var/mobile/Library/Preferences/com.axs.weatherlock.plist"];
    if (![pd isKindOfClass:[NSDictionary class]]) return;
    id v;
    if ((v = pd[@"token"]) && [v isKindOfClass:[NSString class]]) d[@"token"] = v;
    if ((v = pd[@"city"]) && [v isKindOfClass:[NSString class]] && [v length]) d[@"city"] = v;
    if ((v = pd[@"lat"]) && [v isKindOfClass:[NSString class]] && [v length]) d[@"lat"] = v;
    if ((v = pd[@"lon"]) && [v isKindOfClass:[NSString class]] && [v length]) d[@"lon"] = v;

    if ((v = pd[@"size"]))       d[@"size"] = v;
    if ((v = pd[@"huespan"]))    d[@"huespan"] = v;
    if ((v = pd[@"bright"]))     d[@"bright"] = v;
    if ((v = pd[@"offx"]))       d[@"offx"] = v;
    if ((v = pd[@"offy"]))       d[@"offy"] = v;
    if ((v = pd[@"width"]))      d[@"width"] = v;
    if ((v = pd[@"height"]))     d[@"height"] = v;
    if ((v = pd[@"pad"]))        d[@"pad"] = v;
    if ((v = pd[@"gap"]))        d[@"gap"] = v;
    if ((v = pd[@"radius"]))     d[@"radius"] = v;
    if ((v = pd[@"alpha"]))      d[@"bgalpha"] = v;

    // 颜色：填了 hex 就用纯色，否则彩虹
    NSString *hex = nil;
    if ((v = pd[@"colorhex"]) && [v isKindOfClass:[NSString class]]) hex = v;
    if (hex.length > 3) { d[@"color"] = hex; }
    else { d[@"color"] = @"rainbow"; }

    // 背景：hex 优先 > 跟随天气 > 深色
    NSString *bghex = nil;
    if ((v = pd[@"bghex"]) && [v isKindOfClass:[NSString class]]) bghex = v;
    BOOL weatherBG = YES;
    if ((v = pd[@"bgweather"])) weatherBG = [v boolValue];
    if (bghex.length > 3) d[@"bg"] = bghex;
    else d[@"bg"] = weatherBG ? @"weather" : @"dark";

    if ((v = pd[@"hourly"])) d[@"hourly"] = [v boolValue] ? @1 : @0;
    if ((v = pd[@"daily"]))  d[@"daily"]  = [v boolValue] ? @1 : @0;
}

static void loadConfig(void) {
    static NSMutableDictionary *d = nil;
    if (!d) d = [NSMutableDictionary new];
    [d removeAllObjects];
    NSString *raw = [NSString stringWithContentsOfFile:kCfgPath encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!t.length || [t hasPrefix:@"#"]) continue;
        NSRange sp = [t rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *k, *v;
        if (sp.location == NSNotFound) { k = t; v = @"1"; }
        else {
            k = [t substringToIndex:sp.location];
            v = [[t substringFromIndex:sp.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        if (!k.length || !v.length) continue;
        NSScanner *sc = [NSScanner scannerWithString:v];
        double num = 0;
        if ([sc scanDouble:&num] && sc.isAtEnd) d[k] = @(num);
        else d[k] = v;
    }
    mergePrefs(d);
    gCfg = d;
}

// ---------------------------------------------------------------- 彩虹色
static UIColor *hsl(double h, double s, double l) {
    h = fmod(fmod(h, 1.0) + 1.0, 1.0);
    double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    double p = 2 * l - q;
    double (^ch)(double) = ^double(double t) {
        t = fmod(fmod(t, 1.0) + 1.0, 1.0);
        if (t < 1.0 / 6) return p + (q - p) * 6 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
        return p;
    };
    return [UIColor colorWithRed:ch(h + 1.0 / 3) green:ch(h) blue:ch(h - 1.0 / 3) alpha:1];
}

// ---------------------------------------------------------------- 视图
@interface WLView : UIView
@property (nonatomic, strong) NSArray<NSDictionary *> *lines;   // 每项：t 文本 / s 字号 / b 粗体 / c 颜色模式覆盖
@end

@implementation WLView

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat pad = cfgNum(@"pad", 12);

    // ---- 背景
    NSString *bg = cfgStr(@"bg", @"weather");
    UIColor *top = nil, *bot = nil;
    if ([bg isEqualToString:@"none"] || [bg doubleValue] == 0) {
        // 不画背景
    } else if ([bg hasPrefix:@"#"] || [bg isEqualToString:@"color"]) {
        UIColor *c = colorFromHex([bg hasPrefix:@"#"] ? bg : cfgStr(@"bgcolor", @"#101018"), [UIColor blackColor]);
        top = [c colorWithAlphaComponent:0.85];
        bot = [c colorWithAlphaComponent:0.55];
    } else if ([bg isEqualToString:@"dark"] || [bg doubleValue] == 2) {
        top = [UIColor colorWithWhite:0.04 alpha:0.88];
        bot = [UIColor colorWithWhite:0.10 alpha:0.62];
    } else {
        // weather：按 skycon + 昼夜
        NSString *sky = cfgStr(@"sky", @"CLEAR_DAY");
        if ([sky containsString:@"RAIN"]) {
            top = [UIColor colorWithRed:0.06 green:0.16 blue:0.30 alpha:0.85];
            bot = [UIColor colorWithRed:0.13 green:0.30 blue:0.45 alpha:0.55];
        } else if ([sky containsString:@"SNOW"]) {
            top = [UIColor colorWithRed:0.30 green:0.38 blue:0.50 alpha:0.80];
            bot = [UIColor colorWithRed:0.55 green:0.65 blue:0.75 alpha:0.50];
        } else if ([sky containsString:@"CLOUD"] || [sky containsString:@"OVERCAST"] || [sky containsString:@"HAZE"]) {
            top = [UIColor colorWithRed:0.20 green:0.22 blue:0.26 alpha:0.80];
            bot = [UIColor colorWithRed:0.36 green:0.38 blue:0.42 alpha:0.50];
        } else if ([sky containsString:@"NIGHT"]) {
            top = [UIColor colorWithRed:0.05 green:0.06 blue:0.16 alpha:0.85];
            bot = [UIColor colorWithRed:0.12 green:0.16 blue:0.34 alpha:0.55];
        } else {
            top = [UIColor colorWithRed:0.35 green:0.28 blue:0.10 alpha:0.75];
            bot = [UIColor colorWithRed:0.60 green:0.45 blue:0.18 alpha:0.45];
        }
    }

    if (top) {
        CGFloat alpha = cfgNum(@"bgalpha", 0.9);
        if ([bg hasPrefix:@"#"] || [bg isEqualToString:@"color"]) alpha = cfgNum(@"bgalpha", 0.85);
        CGFloat a = MIN(1.0, MAX(0.0, alpha));
        CGGradientRef g = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(),
            (__bridge CFArrayRef)@[(id)[top colorWithAlphaComponent:a * 0.95].CGColor,
                                   (id)[bot colorWithAlphaComponent:a * 0.65].CGColor], NULL);
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, 0), CGPointMake(0, r.size.height), 0);
        CGGradientRelease(g);
    }

    // ---- 边框（radius>0 才画）
    double radius = cfgNum(@"radius", 18);
    if (radius > 0.5) {
        UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(r, 0.5, 0.5)
                                                        cornerRadius:radius];
        [[UIColor colorWithWhite:1 alpha:0.22] setStroke];
        bp.lineWidth = 0.7;
        [bp stroke];
    }

    // ---- 颜色模式
    NSString *colMode = cfgStr(@"color", @"rainbow");
    UIColor *solid = [UIColor whiteColor];
    if ([colMode hasPrefix:@"#"]) solid = colorFromHex(colMode, [UIColor whiteColor]);
    else if ([colMode isEqualToString:@"white"] || [colMode doubleValue] == 1) solid = [UIColor whiteColor];
    else if (![colMode isEqualToString:@"rainbow"] && [colMode doubleValue] == 2)
        solid = colorFromHex(cfgStr(@"colorhex", @"#FFFFFF"), [UIColor whiteColor]);

    double hueSpan = cfgNum(@"huespan", 0.22);
    double sat     = cfgNum(@"sat", 0.90);
    double light   = cfgNum(@"bright", 0.68);
    BOOL rainbow   = [colMode isEqualToString:@"rainbow"] || (![colMode hasPrefix:@"#"] && [colMode doubleValue] == 0 && ![colMode isEqualToString:@"white"]);

    // ---- 文字（UIKit 逐字绘制，自动换行）
    CGFloat yTop = pad + cfgNum(@"top", 0);          // 距离块顶
    CGFloat maxW = r.size.width - pad * 2;
    CGFloat yCursor = yTop;

    for (NSDictionary *ln in self.lines) {
        NSString *text = ln[@"t"];
        if (!text.length) continue;
        CGFloat size = [ln[@"s"] doubleValue];
        if (size <= 0) size = cfgNum(@"size", 14);
        BOOL bold = [ln[@"b"] boolValue];
        UIFont *font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
        CGFloat lineH = font.lineHeight;
        if (yCursor + lineH > r.size.height - pad + 4) break;

        NSShadow *sh = [NSShadow new];
        sh.shadowColor = [UIColor colorWithWhite:0 alpha:0.55];
        sh.shadowBlurRadius = 2.5;
        sh.shadowOffset = CGSizeMake(0, 0);

        __block CGFloat x = pad;
        __block CGFloat yy = yCursor;
        NSUInteger total = text.length;

        [text enumerateSubstringsInRange:NSMakeRange(0, total)
                                  options:NSStringEnumerationByComposedCharacterSequences
                               usingBlock:^(NSString *sub, NSRange subRange, NSRange enclosing, BOOL *stop) {
            NSDictionary *attr = @{NSFontAttributeName: font,
                                   NSForegroundColorAttributeName:
                                       (rainbow ? hsl((double)subRange.location / (double)MAX(1, total - 1) * hueSpan, sat, light) : solid),
                                   NSShadowAttributeName: sh};
            CGSize cw = [sub sizeWithAttributes:attr];
            if (x + cw.width > pad + maxW && x > pad) {       // 换行
                x = pad;
                yy += lineH;
                if (yy + lineH > r.size.height - pad + 4) { *stop = YES; return; }
            }
            [sub drawAtPoint:CGPointMake(x, yy) withAttributes:attr];
            x += cw.width;
        }];

        yCursor = yy + lineH + cfgNum(@"gap", 3);
    }
}
@end

// ---------------------------------------------------------------- 天气
static NSDictionary *gWeather = nil;

static NSString *formatTemp(double v) { return [NSString stringWithFormat:@"%.0f°", v]; }

static NSDictionary *skyMap(void) {
    static NSDictionary *m = nil;
    if (!m) m = @{
        @"CLEAR_DAY": @[@"☀️", @"晴"], @"CLEAR_NIGHT": @[@"🌙", @"晴"],
        @"PARTLY_CLOUDY_DAY": @[@"⛅", @"多云"], @"PARTLY_CLOUDY_NIGHT": @[@"🌙", @"多云"],
        @"CLOUDY": @[@"☁️", @"阴"], @"LIGHT_HAZE": @[@"🌫️", @"轻度霾"],
        @"MODERATE_HAZE": @[@"🌫️", @"中度霾"], @"HEAVY_HAZE": @[@"🌫️", @"重度霾"],
        @"LIGHT_RAIN": @[@"🌧️", @"小雨"], @"MODERATE_RAIN": @[@"🌧️", @"中雨"],
        @"HEAVY_RAIN": @[@"🌧️", @"大雨"], @"STORM_RAIN": @[@"⛈️", @"暴雨"],
        @"LIGHT_SNOW": @[@"🌨️", @"小雪"], @"MODERATE_SNOW": @[@"🌨️", @"中雪"],
        @"HEAVY_SNOW": @[@"❄️", @"大雪"], @"STORM_SNOW": @[@"❄️", @"暴雪"],
        @"FOG": @[@"🌫️", @"雾"], @"WIND": @[@"💨", @"有风"],
        @"LIGHT_WIND": @[@"🌬️", @"微风"], @"STRONG_WIND": @[@"🌪️", @"大风"],
        @"DUST": @[@"💨", @"浮尘"], @"SAND": @[@"💨", @"沙尘"]};
    return m;
}
static NSArray *skyInfo(NSString *sky) {
    NSArray *a = skyMap()[sky];
    return a ? a : @[@"🌤️", @"未知"];
}

static NSString *aqiText(id aqi) {
    double a = [aqi doubleValue];
    if (!a && ![aqi isKindOfClass:[NSNumber class]]) return @"";
    NSString *lv = @"优";
    if (a > 50 && a <= 100) lv = @"良";
    else if (a > 100 && a <= 150) lv = @"轻污";
    else if (a > 150 && a <= 200) lv = @"中污";
    else if (a > 200) lv = @"重污";
    return [NSString stringWithFormat:@"%0.f%@", a, lv];
}

static void buildLines(WLView *v) {
    if (!tokenReady()) {
        v.lines = @[@{@"t": @"锁屏天气：还没填彩云 token", @"s": @(cfgNum(@"size", 14)), @"b": @0}];
        [v setNeedsDisplay];
        return;
    }
    if (!gWeather) {
        v.lines = @[@{@"t": @"天气数据加载中…", @"s": @(cfgNum(@"size", 14)), @"b": @0}];
        [v setNeedsDisplay];
        return;
    }
    NSDictionary *result = gWeather[@"result"];
    NSDictionary *rt = result[@"realtime"];
    if (![rt isKindOfClass:[NSDictionary class]]) return;

    NSString *city = cfgStr(@"city", @"南宁");
    NSString *sky = rt[@"skycon"] ?: @"CLEAR_DAY";
    NSArray *si = skyInfo(sky);
    double temp = [rt[@"temperature"] doubleValue];
    double feel = [rt[@"apparent_temperature"] doubleValue];
    double hum  = [rt[@"humidity"] doubleValue] * 100;

    NSString *uv = @"";
    NSDictionary *li = rt[@"life_index"];
    if ([li isKindOfClass:[NSDictionary class]]) {
        NSDictionary *u = li[@"ultraviolet"];
        if ([u isKindOfClass:[NSDictionary class]]) uv = u[@"desc"] ?: @"";
    }
    NSString *aqi = @"";
    NSDictionary *aq = rt[@"air_quality"];
    if ([aq isKindOfClass:[NSDictionary class]]) {
        id a = aq[@"aqi"];
        if (a) aqi = aqiText(a);
    }

    double size = cfgNum(@"size", 14);
    NSMutableArray *arr = [NSMutableArray new];

    // 第一行：城市 · 图标 · 状态 · 温度
    [arr addObject:@{@"t": [NSString stringWithFormat:@"%@  %@ %@  %@", city, si[0], si[1], formatTemp(temp)],
                     @"s": @(size), @"b": @1}];

    // 第二行：体感 / 湿度 / 紫外线 / AQI
    NSMutableString *l2 = [NSMutableString stringWithFormat:@"体感 %@   💧%.0f%%", formatTemp(feel), hum];
    if (uv.length) [l2 appendFormat:@"   ☀️%@", uv];
    if (aqi.length) [l2 appendFormat:@"   🍃%@", aqi];
    double s2 = cfgNum(@"size2", size * 0.80);
    [arr addObject:@{@"t": l2, @"s": @(s2), @"b": @0}];

    // 第三行：分钟级降水描述
    NSDictionary *mn = result[@"minutely"];
    if ([mn isKindOfClass:[NSDictionary class]] && [mn[@"description"] length]) {
        [arr addObject:@{@"t": [NSString stringWithFormat:@"🌧️ %@", mn[@"description"]],
                         @"s": @(cfgNum(@"size3", size * 0.80)), @"b": @0}];
    }

    // 第四行：未来 3 小时
    if (cfgNum(@"hourly", 1) > 0) {
        NSDictionary *hr = result[@"hourly"];
        NSArray *temps = hr[@"temperature"];
        NSArray *skys = hr[@"skycon"];
        if ([temps isKindOfClass:[NSArray class]] && temps.count >= 3) {
            NSMutableString *ms = [NSMutableString new];
            for (int i = 0; i < 3; i++) {
                NSDictionary *pt = temps[i];
                double t = [pt[@"value"] doubleValue];
                NSString *s = (i < (int)skys.count && [skys[i] isKindOfClass:[NSDictionary class]])
                                ? skyInfo(skys[i][@"value"])[0] : @"";
                [ms appendFormat:@"+%dh %@%.0f°  ", i + 1, s, t];
            }
            [arr addObject:@{@"t": [ms stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]],
                             @"s": @(cfgNum(@"size4", size * 0.72)), @"b": @0}];
        }
    }

    // 第五行：今日最高最低 + 日出日落
    if (cfgNum(@"daily", 1) > 0) {
        NSDictionary *dl = result[@"daily"];
        NSArray *dt = dl[@"temperature"];
        if ([dt isKindOfClass:[NSArray class]] && dt.count) {
            NSDictionary *d0 = dt[0];
            NSMutableString *ms = [NSMutableString stringWithFormat:@"今日 高%.0f° 低%.0f°",
                                   [d0[@"max"] doubleValue], [d0[@"min"] doubleValue]];
            NSArray *astro = dl[@"astro"];
            if ([astro isKindOfClass:[NSArray class]] && astro.count) {
                NSDictionary *a0 = astro[0];
                NSString *rise = a0[@"sunrise"][@"time"];
                NSString *set  = a0[@"sunset"][@"time"];
                if ([rise isKindOfClass:[NSString class]]) [ms appendFormat:@"   🌅%@", rise];
                if ([set isKindOfClass:[NSString class]])  [ms appendFormat:@"   🌇%@", set];
            }
            [arr addObject:@{@"t": ms, @"s": @(cfgNum(@"size5", size * 0.72)), @"b": @0}];
        }
    }

    v.lines = arr;
    [v setNeedsDisplay];
}

// ---------------------------------------------------------------- 窗口
static UIWindow *gWin = nil;
static WLView *gView = nil;
static NSTimer *gTimer = nil;
static NSTimeInterval gLastFetch = 0;
static void fetchWeather(void);

static void relayoutW(CGFloat w) {
    if (!gView) return;
    CGFloat pad = cfgNum(@"pad", 12);
    double width = cfgNum(@"width", 999);
    if (width <= 0 || width > w) width = w - pad * 2;
    CGFloat x = (w - width) / 2 + cfgNum(@"offx", 0);
    CGFloat y = cfgNum(@"offy", 120);
    CGFloat h = cfgNum(@"height", 108);
    gView.frame = CGRectMake(x, y, width, h);
}
static void relayout(void) {
    if (!gWin) return;
    relayoutW(gWin.frame.size.width);
}

static void ensureWindow(void) {
    if (gWin) { relayout(); return; }
    UIApplication *app = [UIApplication sharedApplication];
    UIWindowScene *scene = nil;
    NSUInteger n = 0;
    for (UIScene *s in app.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        n++;
        if (!scene && s.activationState == UISceneActivationStateForegroundActive) scene = (UIWindowScene *)s;
    }
    if (!scene) {
        for (UIScene *s in app.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }
    if (!scene) {
        for (UIWindow *w in app.windows)
            if (w.windowScene) { scene = w.windowScene; break; }
    }
    wlLog(@"ensureWindow scenes=%lu scene=%d", (unsigned long)n, scene != nil);
    if (!scene) return;
    gWin = [[UIWindow alloc] initWithWindowScene:scene];
    gWin.frame = scene.coordinateSpace.bounds;
    gWin.windowLevel = 100000000;
    gWin.backgroundColor = [UIColor clearColor];
    gWin.userInteractionEnabled = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    gView = [[WLView alloc] initWithFrame:CGRectZero];
    gView.backgroundColor = [UIColor clearColor];
    [vc.view addSubview:gView];
    gWin.rootViewController = vc;
    gWin.hidden = YES;
    relayout();
    wlLog(@"window created level=%.0f frame=%@", gWin.windowLevel, NSStringFromCGRect(gWin.frame));
}

static BOOL screenLocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    if (!cls) return NO;
    id inst = nil;
    if ([cls respondsToSelector:@selector(sharedInstanceIfExists)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        inst = [cls performSelector:@selector(sharedInstanceIfExists)];
#pragma clang diagnostic pop
    }
    if (!inst) return NO;
    if ([inst respondsToSelector:@selector(isLocked)])
        return ((BOOL (*)(id, SEL))objc_msgSend)(inst, @selector(isLocked));
    return NO;
}

static void tick(void) {
    loadConfig();
    ensureWindow();
    if (!gWin) return;
    BOOL locked = screenLocked();
    static int lastLocked = -1;
    if ((int)locked != lastLocked) { lastLocked = (int)locked; wlLog(@"locked=%d hidden=%d", (int)locked, (int)gWin.hidden); }
    if (!locked && !gWin.hidden) { gWin.hidden = YES; }
    else if (locked && gWin.hidden) {
        gWin.hidden = NO;
        relayout();
        [gView setNeedsDisplay];
    }
    // 数据刷新与锁屏状态无关，只要窗口/视图在就保持数据新鲜

    // refresh 键被 axs_weather refresh 更新 → 立即拉一次
    static double lastRef = 0;
    double ref = cfgNum(@"refresh", 0);
    if (ref > lastRef) { lastRef = ref; fetchWeather(); }

    if (gWeather == nil || CFAbsoluteTimeGetCurrent() - gLastFetch > cfgNum(@"ttl", 600)) {
        if (CFAbsoluteTimeGetCurrent() - gLastFetch > 45) fetchWeather();
    }
}

// ---------------------------------------------------------------- 拉取
static void fetchWeather(void) {
    if (!tokenReady()) {
        gWeather = nil;
        buildLines(gView);
        return;
    }
    NSString *token = cfgStr(@"token", @"");
    NSString *lat = cfgStr(@"lat", @"22.8170");
    NSString *lon = cfgStr(@"lon", @"108.3665");
    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.caiyunapp.com/v2.5/%@/%@,%@/weather?lang=zh_CN&minutely=true&hourly=true&daily=true&alert=true",
        token, lon, lat];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]
                                                       cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                   timeoutInterval:12];
    [req setValue:@"ColorfulCloudsPro/5.0.10" forHTTPHeaderField:@"User-Agent"];
    gLastFetch = CFAbsoluteTimeGetCurrent();
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!d) return;
            NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            if (![j isKindOfClass:[NSDictionary class]]) return;
            if (![j[@"status"] isEqualToString:@"ok"]) return;
            gWeather = j;
            [d writeToFile:kCachePath atomically:YES];
            NSString *sky = j[@"result"][@"realtime"][@"skycon"];
            if ([sky isKindOfClass:[NSString class]]) {
                NSMutableDictionary *c = [gCfg mutableCopy];
                c[@"sky"] = sky;
                gCfg = c;
            }
            buildLines(gView);
        });
    }] resume];
}

// ---------------------------------------------------------------- 锁屏视图挂载（不依赖 isLocked）
static void attachToLockView(id vc) {
    NSString *cn = NSStringFromClass([(NSObject *)vc class]);
    if (!([cn containsString:@"LockScreen"] || [cn containsString:@"ProudLock"] || [cn containsString:@"CoverSheet"])) return;
    UIView *host = [(UIViewController *)vc view];
    if (!host) return;
    if (host.bounds.size.height < 200) return;      // 跳过零尺寸/小容器
    if (!gView) {
        gView = [[WLView alloc] initWithFrame:CGRectZero];
        gView.backgroundColor = [UIColor clearColor];
    }
    if (gView.superview != host) {
        [gView removeFromSuperview];
        [host addSubview:gView];
    }
    gView.userInteractionEnabled = NO;
    relayoutW(host.bounds.size.width);
    buildLines(gView);
    wlLog(@"attached to %@ bounds=%@", NSStringFromClass([(NSObject *)vc class]), NSStringFromCGRect(host.bounds));
}

static IMP gOrigDidAppear = NULL;
static NSString *gHookClass = nil;
static void wlDidAppear(id self, SEL _cmd, BOOL animated) {
    if (gOrigDidAppear) ((void (*)(id, SEL, BOOL))gOrigDidAppear)(self, _cmd, animated);
    attachToLockView(self);
}

static void installLockHooks(void) {
    if (gHookClass) return;
    NSArray *want = @[@"SBLockScreenViewControllerBase", @"SBLockScreenViewController",
                      @"CSLockScreenViewController", @"SBLockScreenPasscodeViewController"];
    Class target = Nil;
    for (NSString *nm in want) {
        Class c = NSClassFromString(nm);
        if (c && class_getInstanceMethod(c, @selector(viewDidAppear:))) { target = c; break; }
    }
    if (!target) {
        int n = objc_getClassList(NULL, 0);
        if (n > 0) {
            Class *all = (Class *)malloc(sizeof(Class) * n);
            objc_getClassList(all, n);
            for (int i = 0; i < n; i++) {
                NSString *cn = NSStringFromClass(all[i]);
                if ([cn containsString:@"LockScreen"] && [cn containsString:@"ViewController"]
                    && class_getInstanceMethod(all[i], @selector(viewDidAppear:))) { target = all[i]; break; }
            }
            free(all);
        }
    }
    if (!target) { wlLog(@"no lockscreen controller class found"); return; }
    SEL sel = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(target, sel);
    unsigned int cnt = 0;
    Method *list = class_copyMethodList(target, &cnt);
    BOOL owns = NO;
    for (unsigned i = 0; i < cnt; i++) { if (method_getName(list[i]) == sel) { owns = YES; break; } }
    free(list);
    if (owns) {
        gOrigDidAppear = method_setImplementation(m, (IMP)wlDidAppear);
    } else {
        gOrigDidAppear = method_getImplementation(m);
        class_addMethod(target, sel, (IMP)wlDidAppear, method_getTypeEncoding(m));
    }
    gHookClass = NSStringFromClass(target);
    wlLog(@"hooked %@ viewDidAppear owns=%d", gHookClass, (int)owns);
}

// ---------------------------------------------------------------- 启动
__attribute__((constructor))
static void wl_init(void) {
    NSString *proc = [NSProcessInfo processInfo].processName;
    wlLog(@"ctor proc=%@", proc);
    if (![proc isEqualToString:@"SpringBoard"]) return;

    [[NSFileManager defaultManager] createDirectoryAtPath:[kCfgPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    loadConfig();

    NSData *cd = [NSData dataWithContentsOfFile:kCachePath];
    if (cd) {
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:cd options:0 error:nil];
        if (j) gWeather = j;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        installLockHooks();
        ensureWindow();
        buildLines(gView);
        fetchWeather();
        gTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { tick(); }];
    });
}
