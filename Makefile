PREFIX ?= /usr/local
BINARY_NAME = retina-aware
APP_NAME = RetinaAware.app
INSTALL_PATH = $(PREFIX)/bin/$(BINARY_NAME)

build:
	swift build -c release --disable-sandbox
	mkdir -p $(APP_NAME)/Contents/MacOS
	mkdir -p $(APP_NAME)/Contents/Resources
	install .build/release/$(BINARY_NAME) $(APP_NAME)/Contents/MacOS/$(BINARY_NAME)
	chmod +x $(APP_NAME)/Contents/MacOS/$(BINARY_NAME)
	cp Info.plist $(APP_NAME)/Contents/Info.plist
	# Placeholder for Icon
	touch $(APP_NAME)/Contents/Resources/AppIcon.icns

install: build
	sudo rm -rf /Applications/$(APP_NAME)
	sudo cp -R $(APP_NAME) /Applications/
	mkdir -p $(PREFIX)/bin
	sudo ln -sf /Applications/$(APP_NAME)/Contents/MacOS/$(BINARY_NAME) $(INSTALL_PATH)
	# Remove quarantine flag for locally built app
	sudo xattr -rd com.apple.quarantine /Applications/$(APP_NAME) || true

uninstall:
	rm -f "$(INSTALL_PATH)"
	rm -rf "/Applications/$(APP_NAME)"

package: build
	zip -r RetinaAware.zip $(APP_NAME)

.PHONY: build install uninstall package
