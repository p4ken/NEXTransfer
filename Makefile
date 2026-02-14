override APP_NAME := NEXGallery
override BUNDLE_DIR := $(APP_NAME).app
override SOURCES = $(wildcard *.swift)

all: clean build launch

build: FORCE
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	swiftc $(SOURCES) -o "$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)"
	cp Info.plist "$(BUNDLE_DIR)/Contents/Info.plist"

launch: FORCE
	open "$(BUNDLE_DIR)"

clean: FORCE
	rm -rf "$(BUNDLE_DIR)"

format: FORCE
	swift format $(SOURCES) --in-place

FORCE:
