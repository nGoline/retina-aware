PREFIX ?= /usr/local
BINARY_NAME = retina-aware
PLIST_NAME = com.user.retina-aware.plist
INSTALL_PATH = $(PREFIX)/bin/$(BINARY_NAME)
LAUNCH_AGENTS_DIR = $(HOME)/Library/LaunchAgents

install:
	swift build -c release --disable-sandbox
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

.PHONY: install uninstall start-agent stop-agent
