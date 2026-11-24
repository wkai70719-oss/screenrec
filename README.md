# screenrec

A user-initiated macOS screen recorder. It captures the main display and cursor using AVFoundation, and writes H.264 video in an MP4 container with AVAssetWriter. It has no FFmpeg or third-party runtime dependency. No audio is recorded.

## Run

Download the matching artifact from a successful GitHub Actions run, or build as below. In Terminal, change to the directory where you want the video saved and run `./screenrec-universal` (or the architecture-specific binary). The terminal must remain visible: the program prints a recording indicator and the output path. Press Ctrl+C once, then wait for `Saved:` before closing the terminal. Files are stored under `./recordings/` with local date/time names; existing files are not intentionally overwritten. A failed or interrupted recording can leave an incomplete file.

macOS may prompt for Screen Recording permission for the terminal or its host app. Approve it in System Settings (System Preferences on older macOS) > Privacy & Security > Screen Recording, then restart that app and retry if requested. Permission is requested only after the user runs the command. An unsigned downloaded binary may require the normal macOS Gatekeeper approval. Do not run it in a hidden or unattended session.

## Build

On a Mac with Xcode Command Line Tools and Go 1.22.12:

```sh
CGO_ENABLED=1 MACOSX_DEPLOYMENT_TARGET=10.15 go build -o screenrec .
```

The GitHub Actions workflow cross-builds x86_64 and arm64 using the macOS SDK, combines them with `lipo`, and uploads all three executables. The deployment target is 10.15, but compiler targeting does not establish runtime compatibility. Apple Silicon systems require macOS 11 or newer. Go 1.22 is pinned for its macOS 10.15 support; it is an older Go release and should not be treated as receiving current security updates. This is a CLI, not a signed or notarized app.

## Verification status

The Actions build log and artifact for each commit are available from the repository's Actions tab. Build and architecture checks do not verify actual recording. Screen capture permission, visible indicator, first-frame timeout, encoder errors, Ctrl+C finalization, MP4 playback, and compatibility on macOS 10.15 and later on both processor families require interactive tests on real Macs; no such tests are claimed here. The tool uses AVCaptureScreenInput, AVCaptureVideoDataOutput and AVAssetWriter, not SCRecordingOutput. Captured frames may be dropped when the encoder cannot keep up.

