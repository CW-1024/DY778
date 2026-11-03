ARCHS = arm64
TARGET = iphone:clang:16.5:14.0
THEOS ?= $(HOME)/theos
export THEOS_PACKAGE_SCHEME = rootless
export DEBUG = 0
FINALPACKAGE = 1
PACKAGE_VERSION = 1.0-2
INSTALL_TARGET_PROCESSES = Aweme
export DY778_BUILD_TIME := $(if $(DY778_BUILD_TIME),$(DY778_BUILD_TIME),$(shell TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M'))

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = DY778
DY778_FILES = $(wildcard Sources/*.m)
DY778_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -ISources -ffile-prefix-map=$(CURDIR)=. -fdebug-prefix-map=$(CURDIR)=. -DDY778_BUILD_TIME='"$(DY778_BUILD_TIME)"'
DY778_FRAMEWORKS = UIKit Foundation QuartzCore WebKit AVKit AVFoundation QuickLook UserNotifications ImageIO
DY778_LIBRARIES = sqlite3
DY778_LDFLAGS = -lobjc
include $(THEOS_MAKE_PATH)/tweak.mk
