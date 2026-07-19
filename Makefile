override BIN := NEX-6 Wireless Transfer
override BUNDLE := $(BIN).app
override SOURCES = $(wildcard Sources/*.swift)

all: clean icon build launch

build: FORCE
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	swiftc $(SOURCES) -o "$(BUNDLE)/Contents/MacOS/$(BIN)"

icon: FORCE
	mkdir -p "$(BUNDLE)/Contents/Resources"
	iconutil --convert icns --output "$(BUNDLE)/Contents/Resources/AppIcon.icns" AppIcon.iconset
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$(BUNDLE)/Contents/Info.plist"

launch: FORCE
	osascript -e 'quit app "$(BIN)"'
	open "$(BUNDLE)"

clean: FORCE
	rm -rf "$(BUNDLE)"

format: FORCE
	swift format $(SOURCES) --in-place

.PHONY: FORCE
FORCE:
