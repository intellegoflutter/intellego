# Intellego

Read Russian books with stress marks and ё, sentence by sentence, and hear the
same sentence in a Ukrainian audiobook.

- Imports a Russian text from a web page or from loveread (`read_book.php?id=…`).
- Adds missing stress marks and ё (RUAccent dictionaries; optional neural
  disambiguation of homographs such as за́мок / замо́к via ONNX models).
- Splits the text into sentences to practise with.
- Links a YouTube audiobook through its subtitles, aligns Ukrainian and Russian
  sentences, and plays the audio of each sentence. Ukrainian text can be
  corrected (e.g. with an AI assistant) and pasted back.

Targets: Android and Linux desktop.

## Setup

```bash
flutter pub get

# Stress / ё dictionaries are generated, not committed (RUAccent, MIT):
mkdir -p /tmp/ruaccent && cd /tmp/ruaccent
for f in accents yo_words omographs yo_homographs; do
  curl -sLO "https://huggingface.co/ruaccent/accentuator/resolve/main/dictionary/$f.json.gz"
done
cd - && python3 -I tool/build_dictionaries.py /tmp/ruaccent assets/dict

flutter run -d linux
```

Tests: `flutter test`. The neural pipeline has an integration test that
compares against Python RUAccent output:
`INTELLEGO_NN_DIR=<dir with nn/> flutter test integration_test -d linux`.

Playback on Linux needs `cvlc` (VLC); Android uses `just_audio`.

## Credits

See [NOTICE](NOTICE): stress dictionaries and ONNX models come from
[RUAccent](https://github.com/Den4ikAI/ruaccent) (MIT).
