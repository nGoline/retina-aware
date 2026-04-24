# Changelog

All notable changes to this project will be documented in this file.

## [1.2.3] - 2026-04-24
### Fixed
- **Timer Preservation Bug:** Moving the mouse into and out of the Retina display no longer resets a longer active timer (e.g. from a hotkey wake). The longer of the remaining hotkey timer and the base dim delay is always used, so a 10-minute wake survives mouse in/out cycles while a nearly-expired timer correctly defers to the base delay.

## [1.2.2] - 2026-04-10
### Added
- **Universal Distance Logic:** Replaced side-specific positioning with a distance-to-rect algorithm. Works for any monitor arrangement (Left, Right, Above, Below, Diagonal).
- **Pro Hotkey Recorder:** New UI component to record custom keys (letters, numbers, special keys) with proper readable names.
- **Dynamic Icons:** Status bar icon now updates instantly: Sun (Active), Moon (Dimmed), Cloud (Disabled).
- **Tooltips:** Added info icons and tooltips to all configuration settings for better clarity.
- **Packaging:** Added `make package` to generate a release-ready ZIP.

### Fixed
- **Stuck Ramp Bug:** Aggressive state reset ensuring the screen never gets stuck in a partially dimmed state.
- **Grace Period Logic:** Prevents the proximity ramp from overriding an active "full brightness" timer.
- **App Visibility:** Fixed `Info.plist` and `Makefile` permissions so the app opens correctly and shows in the menu bar.
- **Alignment Fix:** Switched from `Form` to custom `VStack` to fix UI shifting issues.
- **Crash Fix:** Improved initialization flow to prevent crashes when enabling the manager.

## [1.2.1] - 2026-04-10
- Initial beta fixes for Launch Agent and basic ramp logic.

## [1.2.0] - 2026-04-10
- Initial feature release with GUI and proximity wake.
