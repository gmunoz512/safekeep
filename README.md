# Sound Photo – PhotoKit Live Photo test harness

One purpose: test whether iOS will save a still photo + frozen-frame video with voice audio as ONE Live Photo asset through PhotoKit (`PHAssetCreationRequest` with `.photo` + `.pairedVideo`).

**Requires a Mac with Xcode 15 or newer (or an Apple cloud build service) and a physical iPhone running iOS 16+.** It was written and syntax-checked on Linux; it has NOT been compiled against the iOS SDK or run on a device.

## Run it
1. Open `SoundPhotoTest.xcodeproj` in Xcode.
2. Select the SoundPhotoTest target > Signing & Capabilities. Pick your Team. If Xcode complains about the bundle ID, the project now uses `com.gmunoz.soundphototest` and team W8YUDW42LL.
3. Plug in the iPhone, choose it as the run destination, press Run. On the phone, trust the developer profile if asked (Settings > General > VPN & Device Management).
4. Tap **Run All Tests (A–E)** and allow full Photos access.
5. Tap **Copy log** and paste the log back into chat.

## What "Run All Tests" does
It saves five test assets, one per experiment, into an album named **Sound Photo Tests**, then prints a summary table.

| Code | Experiment | Why |
|---|---|---|
| A | Baseline: JPEG still + 8.8 s frozen-frame voice video | The main question |
| B | Same, trimmed to 3 s | Normal Live Photos are about 3 s; tests whether length matters |
| C | No still-image-time marker in the video | Tests whether that marker is required |
| D | HEIC still instead of JPEG | The iPhone camera's own format |
| E | CONTROL: still and video carry different pairing IDs | Should fail or not be Live; proves the pairing IDs matter |

For every variant, the app builds both files on the phone. It checks that the IDs match, or deliberately don't for E, and which tracks exist. Then it saves one `PHAssetCreationRequest` with the still as `.photo` and the video as `.pairedVideo`, and logs the full PhotoKit error if there is one. Finally it reads the asset back and logs its identifier, whether iOS classifies it as a Live Photo, which resources Photos stored, and how many items the library gained.

"Create Sound Photo (baseline only)" runs just test A.

## Files
- `SoundPhotoTest/TestRunner.swift` – test matrix, permission, PhotoKit save, album, read-back report
- `SoundPhotoTest/LivePhotoBuilder.swift` – builds the still + frozen-frame MOV and runs the pre-save checks
- `SoundPhotoTest/ContentView.swift` – buttons and log
- `SoundPhotoTest/Resources/` – test image and voice clip

## Record results (in Photos, album "Sound Photo Tests"; A is the oldest)

| Check | A | B | C | D | E |
|---|---|---|---|---|---|
| App log: saved? | | | | | |
| App log: iOS says Live? | | | | | |
| Exactly one new item? | | | | | |
| LIVE badge shown? | | | | | |
| Press-and-hold plays? | | | | | |
| Image stays still? | | | | | |
| Voice audible? | | | | | |
| Seconds of audio played | | | | | |
| Starts immediately? | | | | | |
| Still sharp? | | | | | |
| Works after force-quitting Photos? | | | | | |

Paste the copied log plus this table back into chat.

## Cloud build (no Mac needed)
`.github/workflows/testflight.yml` runs on GitHub-hosted macOS: an unsigned compile check, then archive + export/upload to TestFlight using an App Store Connect API key.
Required repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_TEAM_ID`, `ASC_API_KEY_P8` (full .p8 contents). Build number = `github.run_number`.
