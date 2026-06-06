# AIPace — common developer commands.
# Run `make` or `make help` to see available targets.

SWIFT       ?= swift
PACKAGE_DIR := app
ICONSET     := app/Resources/AppIcon.iconset
ICNS        := app/Resources/AIPace.icns

.DEFAULT_GOAL := help

.PHONY: help build release run test dmg icon clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the app (debug)
	$(SWIFT) build --package-path $(PACKAGE_DIR)

release: ## Build the app (release)
	$(SWIFT) build --package-path $(PACKAGE_DIR) -c release

run: ## Build and launch the menu bar app
	$(SWIFT) run --package-path $(PACKAGE_DIR)

test: ## Run the test suite
	./scripts/test.sh

dmg: ## Build a distributable DMG into dist/ (pass ARGS="--version 1.2.0")
	./scripts/build-dmg.sh $(ARGS)

icon: ## Regenerate the app icon set and .icns from source
	$(SWIFT) scripts/render-app-icon.swift
	iconutil -c icns "$(ICONSET)" -o "$(ICNS)"

clean: ## Remove build artifacts and dist/
	rm -rf $(PACKAGE_DIR)/.build dist
