TARGET := bin/KeyRemappingWatcher
SOURCE := src/KeyRemappingWatcher.m
ARCHS := -arch arm64 -arch x86_64
MIN_VERSION := -mmacosx-version-min=11.0
WARNINGS := -Wall -Wextra -Werror
FRAMEWORKS := -framework Foundation -framework AppKit -framework IOKit

.PHONY: all clean verify

all: $(TARGET) verify

$(TARGET): $(SOURCE)
	@mkdir -p bin
	xcrun clang -fobjc-arc -fblocks $(WARNINGS) $(ARCHS) $(MIN_VERSION) $(FRAMEWORKS) $(SOURCE) -o $(TARGET)
	codesign --force --sign - $(TARGET)

verify:
	plutil -lint resources/com.local.KeyRemapping.plist
	codesign --verify --verbose=2 $(TARGET)
	lipo $(TARGET) -verify_arch x86_64 arm64

clean:
	rm -f $(TARGET)
