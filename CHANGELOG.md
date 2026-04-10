# Changelog

All notable changes to this project will be documented in this file.

## [1.2.1] - 2026-04-10
### Fixed
- **Stuck Ramp Bug:** Fixed an issue where fast mouse movements would leave the Retina display at a partial brightness level. The logic now aggressively resets to dimmed state when exiting the approach zone.
- **Launch Agent Permissions:** Updated `Makefile` to use `launchctl bootstrap` and `bootout` with the correct user domain, removing `sudo` requirements for agent management.
- **Icon Visibility:** Improved app initialization to ensure the menu bar icon always appears, even when launched via Launch Agent.
- **Enable/Disable Logic:** Disabling the app now forces the display to the "Active" state, and re-enabling it returns it to the "Dimmed" state.

### Changed
- Transitioned to Semantic Versioning (SemVer).
- Updated GUI layout for better clarity.

## [1.2.0] - 2026-04-10
- Initial feature-rich release with GUI, status icon, and proximity wake.
