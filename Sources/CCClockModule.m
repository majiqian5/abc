#import "CCClockModule.h"
#import "CCClockContentViewController.h"

@implementation CCClockModule

- (instancetype)init {
    self = [super init];
    if (self) {
        _contentViewController = [[CCClockContentViewController alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_contentViewController release];
    [super dealloc];
}

@end
