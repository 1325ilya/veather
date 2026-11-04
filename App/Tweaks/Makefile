# Builds BTBTweaks.dylib (built-in tweaks) for arm64.
# Output is copied into the app as a resource with the .btbtweak extension so
# Xcode does not try to link it.

SDK ?= iphoneos
CC := $(shell xcrun -sdk $(SDK) -f clang)
SYSROOT := $(shell xcrun -sdk $(SDK) --show-sdk-path)
OUT ?= ../_tweakbuild
SRC := $(wildcard *.m)
# Lua 5.4 (MIT) for the GameGuardian scripts. The io/os/package/debug libraries are left out on purpose:
# they need system()/popen()/dlopen(), which iOS forbids; BTBGGLua.m provides small replacements.
LUA_SRC := $(wildcard lua/*.c)
CFLAGS := -isysroot $(SYSROOT) -arch arm64 -miphoneos-version-min=14.0 \
	-fobjc-arc -O2 -Wall -Wno-unused-function -dynamiclib \
	-framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
	-framework CoreGraphics -weak_framework WebKit \
	-install_name @rpath/BTBTweaks.dylib

all: $(OUT)/BTBTweaks.btbtweak

$(OUT)/BTBTweaks.btbtweak: $(SRC) $(LUA_SRC) $(wildcard *.h) $(wildcard lua/*.h)
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(SRC) $(LUA_SRC) -o $(OUT)/BTBTweaks.btbtweak
	codesign -f -s - $(OUT)/BTBTweaks.btbtweak || true

clean:
	rm -rf $(OUT)
