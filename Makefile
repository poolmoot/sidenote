# Everyday commands. Run `make` with no target to see them.

XCODEGEN_VERSION := 2.46.0
XCODEGEN := .tools/src/XcodeGen/.build/release/xcodegen
APP_NAME := $(shell sed -n 's/^APP_NAME *= *//p' Config/Branding.xcconfig)
CONFIG ?= Debug
ARCH := $(shell uname -m)
DERIVED_DATA := build/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: help bootstrap generate build test run clean

help:
	@echo "make bootstrap  build the pinned XcodeGen into .tools/ (once)"
	@echo "make generate   generate App.xcodeproj from project.yml"
	@echo "make build      build $(APP_NAME).app ($(CONFIG))"
	@echo "make test       run the module tests"
	@echo "make run        build, quit any running copy, and launch"
	@echo "make clean      remove build products and the generated project"

bootstrap:
	@Scripts/bootstrap.sh $(XCODEGEN_VERSION)

generate:
	@test -x $(XCODEGEN) || $(MAKE) bootstrap
	@$(XCODEGEN) generate --quiet

build: generate
	xcodebuild -project App.xcodeproj -scheme App -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS,arch=$(ARCH)' build -quiet

test:
	swift test --package-path Packages/Modules

run: build
	-@pkill -x "$(APP_NAME)"
	open "$(APP_PATH)"

clean:
	rm -rf build App.xcodeproj
