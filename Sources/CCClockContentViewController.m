#import "CCClockContentViewController.h"

@implementation CCClockContentViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor clearColor];

    // 时间标签
    self.timeLabel = [[UILabel alloc] init];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.textColor = [UIColor whiteColor];
    self.timeLabel.font = [UIFont systemFontOfSize:38 weight:UIFontWeightLight];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.timeLabel];

    // 日期标签
    self.dateLabel = [[UILabel alloc] init];
    self.dateLabel.textAlignment = NSTextAlignmentCenter;
    self.dateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    self.dateLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    self.dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.dateLabel];

    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [self.timeLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.timeLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-10],
        [self.dateLabel.topAnchor constraintEqualToAnchor:self.timeLabel.bottomAnchor constant:4],
        [self.dateLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
    ]];

    [self updateTime];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startTimer];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopTimer];
}

- (void)startTimer {
    [self stopTimer];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(updateTime)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stopTimer {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (void)updateTime {
    NSDate *now = [NSDate date];
    NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
    [timeFormatter setDateFormat:@"HH:mm"];
    self.timeLabel.text = [timeFormatter stringFromDate:now];
    [timeFormatter release];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM月dd日 EEEE"];
    [dateFormatter setLocale:[NSLocale currentLocale]];
    self.dateLabel.text = [dateFormatter stringFromDate:now];
    [dateFormatter release];
}

- (void)dealloc {
    [self stopTimer];
    [self.timeLabel release];
    [self.dateLabel release];
    [super dealloc];
}

@end
