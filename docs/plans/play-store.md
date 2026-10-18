# Plan: publish Intellego on Google Play

Status: for later. No Play developer account or store setup exists yet.
Copyright of imported texts and audio is the user's own responsibility, as in
other language-learning apps.

## Account
- Google Play developer account: one-time fee and identity verification.
- New personal accounts must run a closed test with a minimum number of testers
  for about 14 days before they can apply for production. Check the Play Console
  for the current numbers.

## Build and signing
1. Choose the final application ID. `android/app/build.gradle.kts` still has
   the template TODO and `com.intellego.intellego`; it cannot change after the
   first upload.
2. Build an App Bundle. CI only runs
   `flutter build apk --release --split-per-abi`; add
   `flutter build appbundle --release` using the same keystore secrets.
3. Raise `versionCode` on every upload (`pubspec.yaml` is `1.0.0+1`), e.g. from
   the CI run number.
4. Enrol in Play App Signing and use the existing CI key as the upload key.
   Builds sideloaded today are signed with the CI key, so they cannot update
   over a Play-signed install unless that key is supplied as the app-signing
   key; otherwise uninstall first.
5. Target API level comes from `flutter.targetSdkVersion`; it must meet Play's
   current requirement. Native libraries (onnxruntime, ML Kit) must support
   16 KB memory pages. Check both in the pre-launch report.

## Store listing and forms
- App icon 512 px, feature graphic 1024x500, at least 2 phone screenshots.
- Short and full description, category (Education), contact email.
- Privacy policy URL (required: microphone permission and network use).
- Data safety form: speech is recognised on the device; the network is used for
  texts, YouTube audio and model downloads.
- Content rating questionnaire, target audience, ads declaration.
- Check the terms for the downloaded models (see `NOTICE`).

## Release path
Internal testing, then closed testing, then production. Review the
pre-launch report and the Play Console policy status before each step.

## Verification
- `flutter build appbundle --release` succeeds with the release keystore.
- The bundle installs from the internal testing track on a real phone and the
  sync, reading and speaking features work.
