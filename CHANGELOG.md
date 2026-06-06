# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows semantic versioning.

## [Unreleased]

### Added
- "Dynamic" menu bar theme that colors each provider's pill by how much usage is left: neutral (system colors) when healthy, then yellow below 30%, orange below 20%, and red below 10% remaining. It is now the default theme.
- Menu bar "reset time" segment (e.g. `88/23/8h`) showing time until the next window resets, with a matching "Remaining % + reset" display mode that is now the default.
- Menu bar now shows a localized "Login" (or "Error") label when a provider is signed out or failing, instead of silently hiding the pill.
- `Makefile` with common developer commands (build, run, test, dmg, icon, clean).

### Changed
- Default auto-refresh interval is now 1 minute.

### Fixed
- Auto-refresh default was silently ignored on a fresh install: an absent setting read as `0`, which is the `.manual` value, so the documented default never applied. An absent setting now resolves to the default while an explicit Manual choice is preserved.

## [1.1.2] - 2026-04-25

### Added
- Menu bar display name settings for Claude and Codex, limited to 7 characters each

## [1.1.1] - 2026-04-25

### Added
- Remaining percentage display options for the menu bar and popover (Thank you @cifilter)

## [1.1.0] - 2026-04-07

### Added
- Menu bar display mode that shows both usage percentages and pacing insight in the status item

## [1.0.1] - 2026-04-07

### Added
- Launch at startup option in the settings window

### Changed
- The project no longer publishes a GitHub Release workflow
- README now documents building a DMG with the current app version by default
- DMG builds now clear stale Swift module caches before release builds

## [1.0.0] - 2026-04-06

### Added
- First public release of AIPace for macOS
- Menu bar usage display for Claude and Codex `5h` and `weekly` windows
- Main popover with provider cards, pacing insights, refresh controls, and notifications
- Settings window for language, auto refresh, notification sound, menu bar display mode, and custom provider colors
- README screenshots and DMG-based install instructions

## [0.1.0] - 2026-04-06

### Added
- Initial app packaging and release workflow groundwork
