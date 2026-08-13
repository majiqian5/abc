ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

# Rootless 越狱（半越狱）取消下面这行注释
# THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCClockModule
CCClockModule_FILES = Sources/CCClockModule.m Sources/CCClockContentViewController.m
CCClockModule_CFLAGS = -fobjc-arc
CCClockModule_FRAMEWORKS = UIKit
CCClockModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCClockModule_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk
