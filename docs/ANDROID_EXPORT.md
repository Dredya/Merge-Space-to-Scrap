# Android export guide

The project is configured Android-first, but **no APK has been built or verified in this
environment** — the machine has no Android SDK or JDK paths configured in Godot's editor
settings, so the exporter refuses to run. This document is the exact procedure to finish
that step on a machine with the Android toolchain.

## What is already configured

| Setting | Value | Where |
|---|---|---|
| Portrait orientation | `window/handheld/orientation = 1` | `project.godot` |
| Base viewport | 720x1280, `canvas_items` stretch, `expand` aspect | `project.godot` |
| Renderer | `mobile` (2D-only game, cheapest option) | `project.godot` |
| Touch input | `pointing/emulate_mouse_from_touch = true` | `project.godot` |
| Export preset | "Android", arm64-v8a, APK, unsigned release | `export_presets.cfg` |
| Haptics permission | `permissions/vibrate = true` | `export_presets.cfg` |
| Package name | `com.example.scraptospace` (placeholder — change it) | `export_presets.cfg` |

The export attempt in this workspace failed with:

```
A valid Java SDK path is required in Editor Settings.
Invalid Android SDK path in Editor Settings. Missing 'platform-tools' directory!
Missing 'build-tools' directory / apksigner command
```

That is an environment gap, not a project error.

## Prerequisites

1. **Godot 4.7 export templates** — Editor → Manage Export Templates → Download and Install
   (or install a matching `templates/` folder manually).
2. **JDK 17** (Temurin or Android Studio's bundled JDK is fine).
3. **Android SDK** with:
   - `platform-tools` (adb)
   - `build-tools` (apksigner, zipalign)
   - a platform matching the target SDK, e.g. `platforms/android-35`
   - `cmdline-tools/latest`
4. **Debug keystore** (auto-created by the Android tools) and, for release, your own keystore.

## One-time editor setup

In Godot: **Editor → Editor Settings → Export → Android**:

- `Java SDK Path` → e.g. `C:/Program Files/Eclipse Adoptium/jdk-17`
- `Android SDK Path` → e.g. `C:/Users/you/AppData/Local/Android/Sdk`

Then **Project → Install Android Build Template** only if you want the Gradle build
(custom plugins, larger apps). The shipped preset uses the prebuilt template
(`gradle_build/use_gradle_build=false`), so this is optional.

## Build

Set your package name first — `com.example.scraptospace` must not be published as-is.
Changing it later also changes the install identity on devices.

### From the editor

**Project → Export… → Android → Export Project**, choose a path, keep *Export With Debug*
on for a testable build.

### From the command line

```bash
mkdir -p build/android

# Debug (auto-signed with the debug keystore, installable on a device)
godot --headless --path . --export-debug "Android" build/android/scrap-to-space-debug.apk

# Release (requires signing configuration)
godot --headless --path . --export-release "Android" build/android/scrap-to-space.aab
```

Install and check on a connected device:

```bash
adb install -r build/android/scrap-to-space-debug.apk
adb logcat -s godot
```

## Signing a release build

1. Create a keystore:

   ```bash
   keytool -genkeypair -v -keystore scrap-release.keystore \
     -alias scrap -keyalg RSA -keysize 2048 -validity 10000
   ```

2. In the export preset, enable **Package → Signed**, then set the release keystore,
   alias and both passwords (Godot stores these in the preset or asks at export time).

3. **Never commit the keystore or passwords.** `build/` is already git-ignored; keep
   signing material outside the repository too.

4. Prefer an AAB (`gradle_build/export_format=1`) for Play Store upload; APKs are fine
   for direct testing.

## Post-export checklist (not yet performed)

- [ ] App launches in portrait and fills the screen without letterboxing.
- [ ] Safe-area insets: the top bar and bottom nav avoid notches/gesture bars.
- [ ] Drag-to-merge works with a finger; a tap selects without starting a drag.
- [ ] Haptics fire on merge/purchase (requires the VIBRATE permission).
- [ ] Saving survives force-close and the app returning from background.
- [ ] An expedition launched before closing the app is claimable on return.
- [ ] Audio respects the volume sliders and mute.
- [ ] Touch targets are comfortable on a real device (the headless test enforces ≥44 px).

Device-specific behaviour (safe areas, actual haptics, background/foreground handling and
real frame timing) remains **unverified** until this checklist is run on hardware.
