# Plan: develop Intellego on Windows

Status: for later. The Windows machine has no Visual Studio yet.

## Goal
Pull the repo on Windows, run and develop the desktop app there, and keep
syncing with the phone.

## Prerequisites to install
- Git and Flutter 3.47.7 (the version pinned in `.github/workflows/android.yml`).
- **Visual Studio 2022 with the "Desktop development with C++" workload** (or the
  VS Build Tools with the same workload). Flutter cannot build a Windows
  desktop app without it.
- Windows Developer Mode (Flutter uses symlinks for plugins).
- Android Studio (Android SDK, `adb`) and JDK 17/21 for Android builds and the
  USB sync tunnel (`adb reverse tcp:8765 tcp:8765`).

## Steps
1. `git clone https://github.com/intellegoflutter/intellego`, then
   `flutter pub get`. The stress dictionaries in `assets/dict` are committed.
2. Add the Windows runner once: `flutter create --platforms=windows .`
   The repo only has `android/` and `linux/` today. Commit the new `windows/`
   folder.
3. Add a `.gitattributes` with `* text=auto eol=lf` so CRLF line endings do not
   make CI's `dart format --set-exit-if-changed` fail.
4. Replace the Linux-only pieces (the app does not behave like the Linux
   version until this is done):
   - Sentence audio: `VlcSegmentPlayer` in
     `lib/features/playback/segment_player.dart` runs `cvlc`. Needs a Windows
     player (`just_audio` has no Windows support; use e.g. `media_kit` or
     `audioplayers`, or drive `vlc.exe`).
   - Russian speech: `createRussianSpeaker()` in
     `lib/features/speaking/russian_speaker.dart` returns `NoSpeaker` on
     Windows. `flutter_tts` supports Windows, so use `PlatformSpeaker` there
     (a Russian voice must be installed in Windows).
   - YouTube audio: `YtDlpDownloader` already allows Windows but needs
     `yt-dlp.exe` (and node or deno) on PATH.
5. Offline translation stays Android-only (already guarded by
   `NoTranslator`).

## Already fine
Plugins with Windows support: `flutter_onnxruntime`, `flutter_tts`,
`file_picker`, `record`, `path_provider`, `shared_preferences`. The sync server
uses `dart:io`; expect a Windows Firewall prompt the first time it listens.
File paths use `/`, which Windows accepts.

## Verification
- `flutter doctor` shows no problems.
- `flutter analyze lib` and `flutter test` pass.
- `flutter run -d windows`: the library opens, a sentence's audio plays, Russian
  speech works, and "Sync with the phone" syncs with the Android app.
