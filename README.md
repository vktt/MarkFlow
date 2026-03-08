# MarkFlow

MarkFlow is a local-first markdown editor for macOS with split-pane editing and preview, PDF export, and print support.

## Highlights
- Local-only markdown editing (no cloud dependency required)
- Native macOS document workflow with multiple tabs/windows
- Source pane + rendered preview pane
- Cmd-click sync between preview and source
- Export to PDF and print
- Reusable rendering/export package: `MarkFlowEngine`

## Architecture
- `Sources/MarkFlowApp`: SwiftUI macOS app (document UI, commands, sync behavior)
- `Sources/MarkFlowEngine`: reusable renderer/exporter package
- Renderer uses bundled `markdown-it` JavaScript and local CSS/fonts (offline)
- Export/print pipeline uses WebKit -> PDF -> macOS print operation

## Requirements
- macOS 15+
- Xcode 16+ (project currently generated and built with modern Swift/Xcode toolchain)
- `xcodegen` (if regenerating `.xcodeproj` from `project.yml`)

## Quick Start
1. Clone:
```bash
git clone <your-repo-url>
cd MarkFlow
```
2. Generate project:
```bash
./scripts/generate_xcodeproj.sh
```
3. Open in Xcode:
```bash
open MarkFlow.xcodeproj
```
4. Build and run `MarkFlowApp`.

## Build From CLI
Debug build:
```bash
xcodebuild -project MarkFlow.xcodeproj -scheme MarkFlowApp -configuration Debug -derivedDataPath ./.xcodebuild build
```

Release build:
```bash
xcodebuild -project MarkFlow.xcodeproj -scheme MarkFlowApp -configuration Release -derivedDataPath ./.xcodebuild build
```

Artifacts:
- Debug app: `./.xcodebuild/Build/Products/Debug/MarkFlow.app`
- Release app: `./.xcodebuild/Build/Products/Release/MarkFlow.app`

## Tests
Run all package tests:
```bash
swift test
```

## GitHub Release Checklist
1. Ensure `swift test` passes.
2. Build release app.
3. Zip the app bundle:
```bash
cd .xcodebuild/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent MarkFlow.app MarkFlow-macOS.zip
```
4. Create GitHub release and upload `MarkFlow-macOS.zip`.
5. (Recommended) Add checksums and release notes.

## Distribution Note
Current builds are local/sign-to-run-locally. For distribution without Gatekeeper friction, use a Developer ID certificate and notarization.

## Roadmap
- Scroll-sync improvements
- Optional syntax highlighting themes

## License
MIT License. See [LICENSE](LICENSE).

## Third-Party Notices
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for bundled third-party components and attribution.

## Font Licensing Note
The bundled CMU web fonts are intended to be used/distributed under the SIL Open Font License 1.1, based on:
- https://www.checkmyworking.com/cm-web-fonts/

Reference statement from that page: these fonts are released under SIL OFL 1.1 (not legal advice).
