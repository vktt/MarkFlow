# Changelog

All notable changes to this project will be documented in this file.

## [1.0.1] - 2026-03-08

### Fixed
- Fixed preview WebKit setup so the app compiles cleanly on current macOS SDKs.
- Improved window-scoped print routing so print actions target the active document window.
- Fixed source editor Cmd-click behavior by handling `NSNotFound` safely.
- Improved markdown runtime reinitialization behavior to recover from renderer setup failures.

### Improved
- Added safer title extraction from markdown headings for window titles.
- Improved exporter layout stabilization before generating PDF output.
- Added teardown cleanup for preview web message handlers.
- Updated PDF exporter tests to avoid hanging in non-GUI SwiftPM CLI environments.

### Developer Notes
- Version bumped to `1.0.1` (build `2`).
