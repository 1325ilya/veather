# Builds BTBTweaks.dylib (built-in tweaks) for arm64.
# Output is copied into the app as a resource with the .btbtweak extension so
# Xcode does not try to link it.

SDK ?= iphoneos
CC := $(shell xcrun -sdk $(SDK) -f clang)
SYSROOT := $(shell xcrun -sdk $(SDK) --show-sdk-path)
OUT ?= ../_tweakbuild
SRC := $(wildcard *.m)
CFLAGS := -isysroot $(SYSROOT) -arch arm64 -miphoneos-version-min=14.0 \
	-fobjc-arc -O2 -Wall -Wno-unused-function -dynamiclib \
	-framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
	-weak_framework WebKit \
	-install_name @rpath/BTBTweaks.dylib

all: $(OUT)/BTBTweaks.btbtweak

$(OUT)/BTBTweaks.btbtweak: $(SRC) $(wildcard *.h)
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(SRC) -o $(OUT)/BTBTweaks.btbtweak
	codesign -f -s - $(OUT)/BTBTweaks.btbtweak || true

clean:
	rm -rf $(OUT)
