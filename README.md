# Intellego

Read Russian books with stress marks and ё, sentence by sentence, and hear the
same sentence in an audiobook in another language.

## Download (Android)

1. Open the [latest release](https://github.com/intellegoflutter/intellego/releases/latest).
2. Download **`Intellego-…-arm64-v8a.apk`** (right for nearly every phone made
   since 2017; very old phones need `armeabi-v7a`).
3. Open the file on the phone. Android may ask you to allow installing apps
   from your browser or file manager: allow it for this one install.

New versions install over the old one and keep your books. The app is signed
with a fixed key, so updates always work. It is not on Google Play.

## What it does

- Imports a Russian text from a web page or from loveread (`read_book.php?id=…`).
- Adds missing stress marks and ё (RUAccent dictionaries; optional neural
  disambiguation of homographs such as за́мок / замо́к via ONNX models).
- Splits the text into sentences to practise with and marks the ones you did.
- Links a YouTube audiobook in any language through its subtitles (matched with
  the phone's offline translation when the language is not Slavic), shows its
  sentences under the Russian ones and plays the audio of each.
- Extra translation lines per sentence, filled by hand, pasted or translated
  offline on the phone.
- Hear a sentence with a synthetic voice, read it aloud and get feedback from
  on-device speech recognition.
- Syncs books, translations and progress between the phone and the desktop app
  over the local network.
- Text size: Ctrl + mouse wheel or Ctrl +/- on the desktop, pinch on the phone.

Targets: Android and Linux desktop.

## Setup

```bash
flutter pub get

# The stress / ё dictionaries in assets/dict are committed. To rebuild them
# from the RUAccent sources (MIT):
#   mkdir -p /tmp/ruaccent && cd /tmp/ruaccent
#   for f in accents yo_words omographs yo_homographs; do
#     curl -sLO "https://huggingface.co/ruaccent/accentuator/resolve/main/dictionary/$f.json.gz"; done
#   cd - && python3 -I tool/build_dictionaries.py /tmp/ruaccent assets/dict

flutter run -d linux
```

Tests: `flutter test`. The neural pipeline has an integration test that
compares against Python RUAccent output:
`INTELLEGO_NN_DIR=<dir with nn/> flutter test integration_test -d linux`.

Playback on Linux needs `cvlc` (VLC); Android uses `just_audio`.

## Releases

Pushing a tag builds the signed APKs and publishes them as a GitHub release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The *Release* workflow can also be run by hand from the Actions tab: it builds
the same files without publishing, as a check. Every push to `main` also builds
APKs as a workflow artifact (*Android build*).

## Credits

See [NOTICE](NOTICE): stress dictionaries and ONNX models come from
[RUAccent](https://github.com/Den4ikAI/ruaccent) (MIT).
