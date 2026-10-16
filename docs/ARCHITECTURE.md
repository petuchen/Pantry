# Architecture

Everything testable lives in a library target with no UI imports; the app target is thin.

```
PantryCore (library, no SwiftUI)          Pantry (executable)
├─ Models/     ModelEntry, Service,       ├─ PantryApp        entry point + menu commands
│              Category, Format           ├─ AppModel         @MainActor state, calls core
├─ Naming/     name parser, classifier    ├─ DownloadJob      observable download state
├─ Scanning/   one scanner per store      ├─ Support/         theme, settings store
├─ Analysis/   summary, hashing,          └─ Views/           Overview, Models, Cleanup,
│              duplicate detection                            Get Models, Settings, sheets
├─ Removal/    planner + executor
├─ Downloads/  Ollama pull, HF client,
│              HF cache writer
└─ Support/    path safety, sizing, disk
```

## Project layout

```
Pantry/
├─ Package.swift
├─ Sources/
│  ├─ PantryCore/        all logic, no UI imports, unit tested
│  │  ├─ Models/         ModelEntry, ModelService, ModelCategory
│  │  ├─ Naming/         name parser, classifier
│  │  ├─ Scanning/       Ollama, Hugging Face cache and loose-folder scanners
│  │  ├─ Analysis/       storage summary, hashing, duplicates, menu bar title
│  │  ├─ Removal/        planner and guarded executor
│  │  ├─ Downloads/      Ollama pull, Hugging Face client and cache writer
│  │  └─ Support/        path safety, sizing, disk space, formatting
│  └─ Pantry/            SwiftUI app: AppModel, Views/, MenuBar/, Support/
├─ Tests/PantryCoreTests/
├─ docs/                 ARCHITECTURE, UX-REVIEW, NAMING
├─ scripts/              build_dmg.sh, build-app.sh, rename-app.sh, syntax-check.py
└─ .github/workflows/    CI: build and test on macOS, syntax check on Linux
```

## Data flow

```
ScanLocations ──► ModelLibrary.scan ──► [ModelEntry] ──► StorageSummary      (dashboard)
 (env-aware        concurrent scanners        │      └──► DuplicateDetector   (cleanup)
  defaults +                                  │      └──► RemovalPlanner ──► RemovalExecutor
  user folders)                               └──► Table / Inspector
```

`ModelEntry` is the one shape every scanner produces. It carries just enough to answer every
screen's question without touching the disk again:

* `sizeBytes` is the *apparent* size ("how big is this model").
* `exclusivePaths` + `exclusiveBytes` are what only this model owns.
* `blobs` are content-addressed pieces that other models may share (Ollama layers).
* `files` are the large weights files used for exact duplicate detection.

## Where each service keeps models

| Service | Default location | Notes |
|---|---|---|
| Ollama | `~/.ollama/models` (`OLLAMA_MODELS`) | `manifests/<host>/<ns>/<name>/<tag>` (OCI manifest) + `blobs/sha256-<hex>`; config blob gives parameter count and quantization |
| Hugging Face | `~/.cache/huggingface/hub` (`HF_HUB_CACHE`, `HF_HOME`, `XDG_CACHE_HOME`) | `models--<org>--<name>/{blobs,refs,snapshots}`; snapshot files are symlinks into `blobs/` |
| MLX | same Hugging Face cache | `mlx-lm` downloads there. A repo is attributed to MLX when its id contains "mlx" or its `config.json` has a top-level `quantization` block |
| llama.cpp | `~/Library/Caches/llama.cpp` (`LLAMA_CACHE`) | plain `.gguf` files, sidecar `.json`/`.etag` metadata; sharded files grouped |
| Your folders | Settings → "Your own folders" | GGUF files and safetensors model folders, or a Hugging Face cache layout, assigned to a service |

## Key decisions

**Shared storage is counted once.** Two Ollama tags can reference the same weights blob.
`StorageSummary.physicalBytes` sums `exclusiveBytes` plus each distinct blob digest once, so
the dashboard total matches the disk, and `RemovalPlanner` only deletes a blob when *every*
model referencing it is being removed (otherwise it is listed as "kept, shared with X").

**Duplicates are found by content, cheaply.** Files are bucketed by size; only buckets with
two or more distinct physical files are hashed (streaming SHA-256). Ollama blob names already
*are* the SHA-256, so they are never re-read. Symlinks are resolved first, so two Hugging Face
snapshots pointing at one blob are not a duplicate. A typical library hashes nothing at all.

**"Similar" is a name heuristic and says so.** `ModelNameParser` strips org, vendor,
format, quantization, instruct/base and size tokens into a `baseKey` ("llama3.2"). Models are
grouped when keys match, sizes agree within 20% (runtimes report 3.2B vs 3B), and instruct/base
variants don't contradict. Unknown size is never guessed. Groups already explained by an
identical-file group are dropped. The UI labels these "same model, different builds", not
"duplicates".

**Classification is ordered rules + metadata, and always overridable.** Specific purposes are
tested before broad ones (guard → embedding → speech → vision → coding → reasoning → general),
with evidence from Ollama layers/families, `config.json` architectures and model-card
`pipeline_tag`. Users can override any model; overrides persist by id.

**Removal is guarded twice.**
1. `RemovalPlanner` produces an exact plan (paths, bytes, what is kept) shown in the
   confirmation sheet. Manifests are removed before blobs, so an interruption leaves orphaned
   data rather than a model that points at nothing.
2. `RemovalExecutor` refuses any path not strictly inside a known folder, judged after
   resolving symlinks in the *parent* directory. If any path fails, **nothing** is removed.
   Symlinks are removed, never followed. Default action is Move to Trash; permanent delete is
   a separate, separately confirmed button.

   (A plain prefix check is not enough: a symlink inside an allowed folder can point outside it.)

**One model, two surfaces.** `AppModel.shared` is used by the window and by the menu bar item.
The app delegate starts the first scan and a 10-minute refresh loop, so the numbers are live even if
the window was never opened. `refreshIfStale` keeps popover opens instant. What the menu bar label
says is decided by `MenuBarTitle` in the core library, so it is unit tested.

**Downloads match what the tools expect.** Ollama pulls go through the running Ollama's own
`/api/pull` (streamed, aggregated across layers). Hugging Face/MLX downloads write the real
hub cache layout (`blobs/` + relative symlinks + `refs/main`), so `mlx-lm`, `transformers` and
the `hf` CLI see them, and vice versa. GGUF single-file downloads use llama.cpp's
`<org>_<repo>_<file>` naming. Finished blobs are kept on cancel, so a retry resumes at file
granularity. A test writes a cache with the writer and reads it back with the scanner.

## Extending

New service (e.g. LM Studio at `~/.lmstudio/models`): add a case to `ModelService`, implement
`ModelScanner` (or reuse `LooseFolderScanner`), add it to `ModelLibrary.scanners(for:)`, and
add a download path if it has one. Nothing else needs to know.
