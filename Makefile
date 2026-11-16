SHELL := /bin/bash

SWIFT := xcrun swift
APP_BUNDLE := $(CURDIR)/dist/Good Text Viewer.app

.PHONY: build test icon package release run clean

build:
	$(SWIFT) build --configuration release

test:
	$(SWIFT) test --parallel

icon:
	./Scripts/build-icon.sh

package:
	./Scripts/package.sh

release:
	./Scripts/make-release.sh

run: package
	open -n "$(APP_BUNDLE)"

clean:
	$(SWIFT) package clean
	rm -rf -- "$(APP_BUNDLE)"
	-rmdir "$(CURDIR)/dist" 2>/dev/null
