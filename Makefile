PREFIX ?= /usr/local
BINARY_NAME = retina-aware
APP_NAME = RetinaAware.app
PLIST_NAME = com.user.retina-aware.plist
INSTALL_PATH = $(PREFIX)/bin/$(BINARY_NAME)
LAUNCH_AGENTS_DIR = $(HOME)/Library/LaunchAgents

build:
	swift build -c release --disable-sandbox
	mkdir -p $(APP_NAME)/Contents/MacOS
	cp .build/release/$(BINARY_NAME) $(APP_NAME)/Contents/MacOS/$(BINARY_NAME)
	cp Info.plist $(APP_NAME)/Contents/Info.plist

install: build
	# For simplicity in this CLI environment, we install the binary to /usr/local/bin
	# But in a real world, you'd move RetinaAware.app to /Applications
	install ".build/release/$(BINARY_NAME)" "$(INSTALL_PATH)"

uninstall:
	rm -f "$(INSTALL_PATH)"
	$(MAKE) stop-agent || true
	rm -f "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

start-agent:
	mkdir -p "$(LAUNCH_AGENTS_DIR)"
	cp "$(PLIST_NAME)" "$(LAUNCH_AGENTS_DIR)/"
	launchctl load "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

stop-agent:
	launchctl unload "$(LAUNCH_AGENTS_DIR)/$(PLIST_NAME)"

.PHONY: build install uninstall start-agent stop-agent
