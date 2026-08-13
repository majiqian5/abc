#import <UIKit/UIKit.h>

@interface CCClockContentViewController : UIViewController
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) NSTimer *timer;
@end
