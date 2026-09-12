APP     := ParrotPane
BUNDLE  := build/$(APP).app
BINARY  := $(BUNDLE)/Contents/MacOS/$(APP)
SOURCES := $(wildcard Sources/*.swift)
FLAGS   := -swift-version 5 -O -target arm64-apple-macos14.4

.PHONY: all run install clean

all: $(BINARY)

$(BINARY): $(SOURCES) Resources/Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Resources/ParrotPane.icns $(BUNDLE)/Contents/Resources/ParrotPane.icns
	@swiftc $(FLAGS) $(SOURCES) -o $(BINARY)
	@codesign --force --sign - --identifier dev.local.parrotpane $(BUNDLE) 2>/dev/null
	@echo "built $(BUNDLE)"

run: all
	@$(BINARY) $(ARGS)

install: all
	@mkdir -p $(HOME)/.local/bin
	@ln -sf $(CURDIR)/bin/parrotpane $(HOME)/.local/bin/parrotpane
	@echo "linked $(HOME)/.local/bin/parrotpane -> $(CURDIR)/bin/parrotpane"

clean:
	@rm -rf build
