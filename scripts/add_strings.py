# -*- coding: utf-8 -*-
"""Adds or replaces English + Turkish entries in a String Catalog (.xcstrings).

Usage from another script, run at the repository root:

    from scripts.add_strings import write
    write("Packages/CueTakeKit/Sources/EditorFeature/Resources/Localizable.xcstrings", {
        "editor.example": ("Example", "Örnek"),
        "editor.count %lld": ("%lld clips", "%lld klip"),
    })

Keys are what `Text("key", bundle: .module)` / `String(localized:bundle:)` use. Interpolated
values become %@ (strings) or %lld (integers) in the key; positional %1$@ in the value.
Entries are marked "manual" so Xcode does not remove them, and the file is kept sorted.
"""
import collections
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def entry(en, tr):
    return collections.OrderedDict([
        ("extractionState", "manual"),
        ("localizations", collections.OrderedDict([
            ("en", {"stringUnit": {"state": "translated", "value": en}}),
            ("tr", {"stringUnit": {"state": "translated", "value": tr}}),
        ])),
    ])


def write(path, new):
    path = os.path.join(ROOT, path)
    if os.path.exists(path):
        d = json.load(io.open(path, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    else:
        d = collections.OrderedDict([("sourceLanguage", "en"), ("strings", collections.OrderedDict()), ("version", "1.0")])
    for key, (en, tr) in new.items():
        d["strings"][key] = entry(en, tr)
    d["strings"] = collections.OrderedDict(sorted(d["strings"].items()))
    io.open(path, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
    print(path, len(d["strings"]))
