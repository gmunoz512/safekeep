# safekeep

Add a voice note to a photo, and keep it forever.

Safekeep turns a photo plus a voice clip into a single Live Photo, so pressing and holding the photo plays the voice back. It saves a new copy and never touches the original. It's built mostly for iMessage: copy a voice note, open Safekeep in Messages, pick a photo, done.

## features

- **iMessage app**: pick a recent photo and paste a copied voice note without leaving Messages
- **share extension**: send audio to Safekeep from other apps
- **live photo builder**: pairs the still with a frozen-frame video carrying the audio, so Photos treats it as one Live Photo
- **non-destructive**: saves a new copy into a "Safekeep" album; the original stays as-is
- handles iCloud photos (downloads full resolution first) and longer clips

## stack

- Swift + SwiftUI, iOS 16+
- PhotoKit (`PHAssetCreationRequest` with `.photo` + `.pairedVideo`)
- AVFoundation for building the paired video
- Messages and Share extensions sharing code in `Shared/`

## build

1. Open `SoundPhotoTest.xcodeproj` in Xcode (the project still uses its original name).
2. In Signing & Capabilities, pick your own team for the app and both extensions, and change the bundle IDs if needed.
3. Run on a real iPhone; Live Photos and the Messages extension don't really work in the simulator.

`.github/workflows/testflight.yml` builds and uploads to TestFlight on GitHub's macOS runners using App Store Connect API key secrets.
