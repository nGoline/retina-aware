PREFIX ?= /usr/local
BINARY_NAME = retina-aware
APP_NAME = RetinaAware.app
PLIST_NAME = com.user.retina-aware.plist
INSTALL_PATH = $(PREFIX)/bin/$(BINARY_NAME)
LAUNCH_AGENTS_DIR = $(HOME)/Library/LaunchAgents
UID = $(shell id -u)

build:
	swift build -c release --disable-sandbox
	mkdir -p $(APP_NAME)/Contents/MacOS
	cp .build/release/$(BINARY_NAME) $(APP_NAME)/Contents/MacOS/$(BINARY_NAME)
	cp Info.plist $(APP_NAME)/Contents/Info.plist

install: build
	# Copy to /Applications for standard bundle behavior
	mkdir -p /Applications/$(APP_NAME)
	cp -R $(APP_NAME)/ /Applications/$(APP_NAME)/
	# Also symlink to /usr/local/bin for CLI usage
	mkdir -p $(PREFIX)/bin
	ln -sf /Applications/$(APP_NAME)/Contents/MacOS/$(BINARY_NAME) $(INSTALL_PATH)

uninstall:
	rm -f "$(INSTALL_PATH)"
	rm -rf "/Applications/$(APP_NAME)"
	$(MAKE) stop-agent || true
	rm -f "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

start-agent:
	mkdir -p "$(LAUNCH_AGENTS_DIR)"
	cp "$(PLIST_NAME)" "$(LAUNCH_AGENTS_DIR)/"
	launchctl bootstrap gui/$(UID) "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

stop-agent:
	launchctl bootout gui/$(UID) "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)" || true

.PHONY: build install uninstall start-agent stop-agent
