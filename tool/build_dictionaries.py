#!/usr/bin/env python3
"""Converts RUAccent dictionaries (MIT, huggingface.co/ruaccent/accentuator)
into the compact assets used by the app.

Usage: python3 -I tool/build_dictionaries.py <dir with *.json.gz> assets/dict

Inputs:  accents.json.gz, yo_words.json.gz, yo_homographs.json.gz, omographs.json.gz
Outputs: stress.dat   sorted lines "word\\tindex" (index of the stressed vowel)
         stress.idx   sparse index "firstWord\\tbyteOffset" for every BLOCK lines
         yo_words.json, omographs.json (word -> variants), yo_homographs.json (word -> ё-form)
"""
import gzip
import json
import re
import sys
from pathlib import Path

BLOCK = 128
VOWELS = set("аеёиоуыэюя")
WORD = re.compile(r"[а-яё]+(?:-[а-яё]+)*")


def load(src: Path, name: str):
    with gzip.open(src / f"{name}.json.gz", "rt", encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)

    accents = load(src, "accents")
    rows = []
    for word, marked in accents.items():
        # ё always carries the stress and monosyllables stay unmarked.
        if not WORD.fullmatch(word) or "ё" in word or marked.count("+") != 1:
            continue
        if sum(c in VOWELS for c in word) < 2:
            continue
        pos = marked.index("+")
        if marked.replace("+", "") != word or word[pos] not in VOWELS:
            continue
        rows.append((word, pos))
    rows.sort()

    offset = 0
    index_lines = []
    with open(dst / "stress.dat", "wb") as dat:
        for i, (word, pos) in enumerate(rows):
            line = f"{word}\t{pos}\n".encode("utf-8")
            if i % BLOCK == 0:
                index_lines.append(f"{word}\t{offset}\n")
            dat.write(line)
            offset += len(line)
    (dst / "stress.idx").write_text("".join(index_lines), encoding="utf-8")

    yo = load(src, "yo_words")
    (dst / "yo_words.json").write_text(
        json.dumps(yo, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    for name in ("omographs", "yo_homographs"):
        table = load(src, name)
        if name == "omographs":
            table["коса"] = ["к+оса", "кос+а"]  # RUAccent hardcodes this entry
        (dst / f"{name}.json").write_text(
            json.dumps(table, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    print(f"stress entries: {len(rows)}, blocks: {len(index_lines)}, bytes: {offset}")


if __name__ == "__main__":
    main()
