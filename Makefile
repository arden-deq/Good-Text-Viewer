SHELL := /bin/bash

CMAKE_BIN ?= cmake
CTEST_BIN ?= ctest
BUILD_DIR := $(CURDIR)/.build/qt-local
APP_BUNDLE := $(CURDIR)/dist/qt/Good Text Viewer.app

.PHONY: build test icon package release run clean

build:
	$(CMAKE_BIN) -S . -B "$(BUILD_DIR)" -DCMAKE_BUILD_TYPE=Release
	$(CMAKE_BIN) --build "$(BUILD_DIR)" --config Release --parallel

test: build
	$(CTEST_BIN) --test-dir "$(BUILD_DIR)" --build-config Release --output-on-failure

icon:
	./Scripts/build-icon.sh

package:
	CMAKE_BIN="$(CMAKE_BIN)" bash ./Scripts/package.sh

release:
	CMAKE_BIN="$(CMAKE_BIN)" bash ./Scripts/make-release.sh

run: package
	open -n "$(APP_BUNDLE)"

clean:
	$(CMAKE_BIN) --build "$(BUILD_DIR)" --target clean
