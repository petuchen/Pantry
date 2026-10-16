# Changelog

All notable changes to Pantry are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Menu bar item: icon with the total size beside it, or the download percentage while a
  download runs. The popover shows the total, storage by service, running downloads with a
  cancel button, a cleanup hint, Open Pantry, Settings and Quit.
- Settings → Menu bar: show or hide the menu bar item, show or hide the size text, and show or
  hide the Dock icon (menu-bar-only mode). Turning the menu bar item off always restores the
  Dock icon so the app can't become unreachable.
- Pantry keeps running after the window is closed. It scans at launch and every 10 minutes, and
  rescans when the popover opens if the last scan is more than 30 seconds old.
- `MenuBarTitle` in the core library, with unit tests, deciding the text shown in the menu bar.
- `scripts/build_dmg.sh`: runs tests, makes a release build, assembles and signs `Pantry.app`,
  and writes `build/Pantry.dmg`. Prints a failure summary when tests fail. Supports
  `--skip-tests`, `--sign` and `--notarize`. `scripts/release.sh` is an alias.
- This changelog.

### Changed
- The main window is now a single `Window` scene instead of a `WindowGroup`.
- The README is shorter and links here for details.
- `build-app.sh` no longer passes `--arch arm64` to `swift build`.

### Fixed
- Expected total size in `LooseFolderScannerTests.testSafetensorsDirectoryIsOneModelAndNotDescendedInto`
  (732 bytes, including the 2-byte `config.json`).

### Removed
- References to private projects from the documentation.

### Added
- App icon and menu bar glyph from `resources/` are bundled by the build scripts (build fails if missing).
- Menu bar uses the bundled glyph as a template image (SF Symbol fallback; arrow while downloading).

## [0.1.0] - 2026-10-07

Initial version.

### Added
- Scanners for Ollama (manifests and content-addressed blobs), the Hugging Face hub cache
  (including MLX models), llama.cpp / loose GGUF files, and user-added folders.
- Model classification into general, coding, reasoning, vision, image generation, embedding,
  speech, safety/policy judge and reranker, with per-model overrides that persist.
- Name parsing that makes `llama3.2:3b`, `Llama-3.2-3B-Instruct-4bit` and
  `Meta-Llama-3.2-3B-Instruct-Q4_K_M.gguf` comparable.
- Overview dashboard: total storage, breakdown by service and by use, largest models, free disk
  space. Storage shared between models is counted once.
- Models table with search, filters, sorting, an inspector and a context menu.
- Cleanup: identical files (size bucketing, then streaming SHA-256) and lookalike models.
- Removal: exact plan shown before anything changes, Move to Trash by default, separately
  confirmed permanent delete, shared layers kept, and a guard that refuses any path outside the
  known model folders (symlink escapes included).
- Downloads: Ollama pull through the local Ollama API, and Hugging Face / MLX / single-GGUF
  downloads written in the standard Hugging Face cache layout. Size and free space checked first.
- Settings for extra folders and Hugging Face sign-in status.
- 83 unit tests, CI workflow, `rename-app.sh`, `build-app.sh`, and documentation
  (architecture, UX review, naming).
