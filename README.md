<p align="center">
  <img src="resources/AppIcon-1024.png" width="128" alt="Pantry app icon">
</p>

<h1 align="center">Pantry</h1>

**See, fetch and clear out the local AI models on your Mac.**

Ollama, llama.cpp, MLX and Hugging Face each keep models in a different folder. Pantry reads
all of them, shows what you have and what it costs, helps you download more, finds copies you
don't need, and removes things only when you say so.

<p align="center">
  <a href="https://github.com/petuchen/Pantry/releases"><img alt="Release" src="https://img.shields.io/github/v/release/petuchen/Pantry?include_prereleases&sort=semver"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange">
  <a href="https://github.com/petuchen/Pantry/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/petuchen/Pantry/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

<p align="center">
  <img src="docs/screenshots/overview.png" width="720" alt="Pantry overview: total size, storage by service, what the models are for, largest models">
</p>

## Features

| | |
|---|---|
| **Overview** | Total storage, breakdown by service and by use, largest models, free disk space, and one callout when there is something to clean up. |
| **Models** | Every model in one sortable table: service, what it's used for (general, coding, reasoning, vision, image generation, embedding, speech, safety/policy judge, reranker), size, date. Search, filters, and an inspector showing exactly how much space a removal would free. |
| **Get Models** | Pull from **Ollama** (paste a name, an `ollama run …` command or a link), or search **Hugging Face / MLX / GGUF** and download a whole repo or a single quantization. Size and free space are checked first; progress is real bytes. |
| **Cleanup** | *Identical copies* (same bytes, found by content hash) and *same model, different builds* (for example `llama3.2:3b` in Ollama and a 4-bit MLX conversion). |
| **Menu bar** | An icon with the total size (or download %) beside it. The popover shows the breakdown by service, running downloads with cancel, and a cleanup hint, without opening the window. |
| **Removal** | Always confirmed, with exact items and bytes. Defaults to Move to Trash; permanent delete is a separate, second-confirmed button. Shared Ollama layers are kept while another model still uses them. |

"Used for" is a best guess from the name and metadata. You can correct any model from its
context menu and Pantry remembers.

## Install

Requires macOS 14+ and Xcode 15+ (or the Swift 5.9+ command line tools).

```bash
git clone https://github.com/petuchen/Pantry.git && cd Pantry
swift run Pantry                 # run from Terminal
swift test                       # run the unit tests
./scripts/build_dmg.sh           # test + release build + build/Pantry.dmg
```

`build_dmg.sh` stops and prints a summary if a test fails. Useful options:

```bash
./scripts/build_dmg.sh --skip-tests
./scripts/build_dmg.sh --sign "Developer ID Application: Name (TEAMID)" --notarize PROFILE
```

You can also `open Package.swift` and press Run in Xcode. The default build is ad-hoc signed,
which is fine on the Mac that built it. On another Mac, right-click the app and choose Open
once. Change `BUNDLE_ID` at the top of `scripts/build_dmg.sh` before distributing.

Pantry is not sandboxed (it has to read and delete in other tools' folders), so it can't go on
the Mac App Store. If macOS asks for access to a folder or external drive, allow it.

## Where it looks

| Service | Default folder | Override |
|---|---|---|
| Ollama | `~/.ollama/models` | `OLLAMA_MODELS` |
| Hugging Face | `~/.cache/huggingface/hub` | `HF_HUB_CACHE`, `HF_HOME`, `XDG_CACHE_HOME` |
| MLX | same Hugging Face cache (where `mlx-lm` downloads) | |
| llama.cpp | `~/Library/Caches/llama.cpp` | `LLAMA_CACHE` |
| Anything else | Settings → *Your own folders* (GGUF files, safetensors folders, another HF cache) | |

Apps launched from Finder don't inherit shell environment variables. If you set
`OLLAMA_MODELS` in `.zshrc`, add that folder under Settings instead.

Gated Hugging Face models: run `hf auth login` once. Pantry reads the token the CLI saves and
never stores it.

## Privacy

No account, no telemetry, no analytics. The only network calls are the ones you ask for:
Ollama on `localhost`, and `huggingface.co` for search and downloads.

## What's new

Version 0.1.1, the first public release:

* Scans Ollama, Hugging Face, MLX, llama.cpp and your own folders into one library.
* Dashboard with storage by service and by use; shared layers counted once.
* Duplicate and lookalike detection, with guarded, confirmed removal.
* Downloads for Ollama and Hugging Face / MLX / GGUF.
* Menu bar item with a glanceable popover; the app keeps running when the window is closed.
* One-command build, test and DMG script.

Full details in [CHANGELOG.md](CHANGELOG.md).

## Tests

`swift test` runs the unit tests against real files built in temporary folders (Ollama
manifests and blobs, Hugging Face caches with symlinks, sharded GGUFs). They cover scanning,
classification, duplicate detection, removal safety rules and download parsing. The SwiftUI
layer is thin and not unit tested; downloads are tested by parsing and file layout, not
against live servers.

## Known limitations

* Duplicate detection hashes files that share an exact size; a very large duplicate takes a
  while (it runs in the background).
* "Similar model" matching is name based and conservative: an unknown parameter size is never
  guessed, so some real matches are missed rather than wrongly merged.
* An interrupted Hugging Face download restarts the current *file* from zero (finished files are kept).
* Only `models--*` entries of the Hugging Face cache are listed.
* The Ollama suggestions in *Get Models* are hard-coded and may drift from the library.
* LM Studio, Jan, GPT4All and similar aren't built in; add their folder as a custom folder, or
  see "Extending" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Docs

* [Architecture](docs/ARCHITECTURE.md): project layout, data flow, where each service stores
  models, and how removal and duplicate detection work.
* [UX review](docs/UX-REVIEW.md): the interface reviewed against the Laws of UX.
* [Changelog](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE).

## Credits

Menu bar glyph: "cat" from [Griddy Icons](https://github.com/griddy-icons/griddy-icons) by Zuzana Benova (MIT); see `resources/MenuBarGlyph-LICENSE.txt`.
