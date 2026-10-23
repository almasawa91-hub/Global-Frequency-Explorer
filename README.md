# Global Frequency Explorer

A Flutter Android radio explorer featuring a dark world map, Radio Browser station discovery, station markers, favorites, popular stations, and a compact live audio player.

## Build
The GitHub Actions workflow generates Android platform files, resolves Flutter packages, runs static analysis and tests, builds a debug APK, and uploads it as an artifact.

1. Create a GitHub repository named `Global-Frequency-Explorer`.
2. Upload the contents of this folder to its `main` branch.
3. Open **Actions** and select **Flutter Android APK**.
4. Download `global-frequency-explorer-debug-apk` from a successful run.

## Notes
- Station discovery uses the Radio Browser API.
- Some stations lack valid coordinates or have unavailable streams.
- Background playback and lock-screen controls require the Android audio-service integration and platform notification/foreground-service configuration; this starter currently provides foreground playback and the UI foundation.
- Map tiles are provided by CARTO and require internet access.
