override BIN := NEX-6 Wireless Transfer
override BUNDLE := $(BIN).app
override SOURCES = $(wildcard Sources/*.swift)

all: clean build launch

build: FORCE
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	swiftc $(SOURCES) -o "$(BUNDLE)/Contents/MacOS/$(BIN)"

launch: FORCE
	open "$(BUNDLE)"

clean: FORCE
	rm -rf "$(BUNDLE)"

format: FORCE
	swift format $(SOURCES) --in-place

.PHONY: FORCE
FORCE:
