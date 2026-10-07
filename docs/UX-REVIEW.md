# UX review (Laws of UX)

Method: the ten laws from Jon Yablonski's *Laws of UX*, applied as a checklist to each screen,
then turned into team principles in the *principle → law → rule* form so they can be argued
with in future reviews. These are heuristics, **not** user research: nothing here has been
tested with real people yet (see "Open questions" at the end).

## Design principles

| Principle | Grounded in | Checkable rule |
|---|---|---|
| **Nothing leaves your disk by surprise.** | Peak-End Rule; deliberate friction | Every removal shows the exact items and bytes freed first. Default action is Move to Trash. Permanent delete is a separate button *and* a second confirmation. The executor refuses any path outside known model folders. |
| **Speak the Mac's language.** | Jakob's Law | Sidebar + table + inspector, ⌘R rescan, ⌘F search, ⌘, settings, ⌫ to remove, right-click menu, Finder-style sizes, standard sheets. No custom navigation. |
| **Decide for me, then let me correct.** | Tesler's Law | Locations come from each tool's env vars, categories are auto-assigned, shared storage is de-duplicated in the numbers. Anything guessed has an override (category menu) or says it is a guess ("look like the same model"). |
| **One recommended path per screen.** | Hick's Law | ≤ 4 sidebar items; filters default to "All"; at most one prominent button per view; removal sheet has one default. |
| **Be liberal in what you accept.** | Postel's Law | Model fields accept bare names, `ollama run …`, `hf download …` and web URLs. A bad folder is a warning, never a failed scan. Errors say what to do next. |
| **Never make people wait without telling them why.** | Doherty Threshold | First paint < 400 ms (skeleton, then results). Anything longer shows what is happening; long transfers show bytes done / total. |
| **Make the end of a task feel finished.** | Peak-End Rule | Removal ends with "Moved 2 models to the Trash · 7.8 GB freed when you empty it"; downloads end with "Ready to use"; an empty Cleanup says so with a positive state. |

## Screen-by-screen

**Overview** (the first screen, so it carries the Aesthetic-Usability weight)
* *Miller*: four chunks, in reading order: total → by service → by use / largest → cleanup.
  Sizes are formatted (4.7 GB), never raw bytes.
* *Von Restorff*: exactly one element gets the accent treatment, the cleanup callout, and only
  when there is something to act on. Everything else is neutral.
* *Fitts*: every row in the service, use and largest lists is a full-width click target that
  jumps to the filtered Models view. Primary "Review" is large.
* *Doherty*: a skeleton in the final layout while scanning, so nothing jumps.
* *Peak-End*: the zero state ("No duplicate models found") is a pleasant ending, not a blank.
* *Tesler*: "Layers that several Ollama models share are counted once" so the total matches the
  disk without the user doing arithmetic.

**Models**
* *Jakob*: a sortable `Table`, search field, inspector panel, context menu. Double-click
  opens details.
* *Hick*: two filters, both defaulting to "All". Technical detail is behind a disclosure.
* *Fitts*: **Remove…** is the least prominent button and sits at the opposite end of the
  window from filters and the Details toggle, so it can't be hit while reaching for them.
* *Tesler*: the status bar says "frees X if removed" using the shared-aware plan, so people
  don't remove a model expecting 4 GB and get 40 MB.

**Cleanup**
* *Hick / Tesler*: the app finds the groups; the user only picks what to keep. Identical
  copies and "same model, different builds" are separated because they carry different
  certainty, and the second says only the user can decide.
* *Von Restorff*: nothing is pre-selected or highlighted as "delete this", deliberately
  (see Responsible use).
* *Miller*: each group is one card of 2–4 rows with the same fields in the same order.

**Get Models**
* *Hick*: one segmented control picks the source; the default list is "Most downloaded", so
  there is always something to click. Six starting points for Ollama, labelled by purpose.
* *Postel*: paste anything; the app says what it will pull ("Will pull llama3.2").
* *Doherty*: the first list renders immediately; typing is debounced (350 ms); progress is
  determinate and shows bytes done of total.
* *Tesler*: size and free space are checked *before* download starts; the button disables with
  a reason rather than failing at 80%.

**Menu bar** (the glanceable surface; most people will see this far more often than the window)
* *Miller / Hick*: the popover answers four questions in order and nothing else: how much? (one
  big number) → where? (service bar + rows) → anything running? (downloads) → anything to do?
  (one cleanup button). No filters, no table, no settings inside it.
* *Doherty*: opening it never waits on a scan; it shows the last result, and rescans in the
  background only if that result is older than 30 s. The icon text hides until the first scan
  finishes instead of flashing "Zero KB".
* *Peak-End*: while a download runs, the icon text becomes its percentage, so the thing you are
  waiting for is visible without opening anything.
* *Von Restorff*: the cleanup button is the only accent-coloured element, and appears only when
  there is something to act on.
* *Fitts*: every row is a full-width target that opens the window on the right screen; Quit sits
  at the opposite end from Open Pantry.
* *Jakob*: standard `MenuBarExtra` popover, ⌘Q to quit, gear for Settings, and a setting to hide
  the Dock icon like other menu bar utilities.
* *Responsible use*: no badges, no notifications, no pulsing. The icon only changes for a
  download the user started. Hiding the menu bar item forces the Dock icon back on so the app can
  never become unreachable.

**Removal sheet**
* *Peak-End*: this is the highest-stakes moment, so it gets the most care: exact names, exact
  bytes, what is kept and why, what Trash means for disk space.
* *Fitts*: "Delete Permanently…" is far left, plain; "Move to Trash" is the default (↩) at the
  right; Cancel (⎋) sits between. The dangerous action is never adjacent to the default.
* *Deliberate friction*: permanent delete needs a second confirmation. Friction is intentional
  here and nowhere else.

## Findings during review

* **Fixed:** the Hugging Face search debounce also delayed the *initial* list by 350 ms
  (Doherty). Now only typed queries are debounced.
* **Decision, not a bug:** "Frees X" is shown even when the action is Move to Trash, where
  space isn't freed until the Trash is emptied. The sheet and the completion banner both say
  so explicitly.

## Responsible use

* No engagement mechanics: no streaks, badges, notifications, or "you could free X GB!" nags.
  The cleanup callout is phrased as an upper bound ("Up to…") and only appears when true.
* No default that works against the user: nothing is pre-selected for deletion; the safest
  action is the default; the app never removes anything on its own.
* No telemetry, no account. The only network calls are the ones the user asks for (Ollama on
  localhost, huggingface.co). The Hugging Face token is read, never stored.
* Edge cases tested in code (`Tests/`): interrupted downloads are flagged, not hidden; shared
  blobs are never deleted from under another model; paths outside known folders are refused;
  symlinks are removed but never followed.

## Open questions

1. **No usability testing.** Suggested first round, 5 people who use at least two of the four
   tools: (a) "How much space do your models use, and which service uses most?" (b) "Download
   a small coding model." (c) "Find anything you have twice." (d) "Free about 10 GB." (e) "Undo
   what you just did." Watch for hesitation at the removal sheet and misreading "Frees".
2. **No visual pass.** (This includes the menu bar popover: check its width, and how the icon text looks on a notched display crowded with other menu bar items.) Check
   spacing, truncation, and dark mode on a real Mac.
3. **Colour.** The service bar relies on tint to tell segments apart; the legend below carries
   names and percentages, but the bar itself isn't distinguishable for colour-blind users.
   Follow-up: direct labels or hatching on segments.
4. **Target size.** Primary buttons are `.large` and rows are full-width, but table rows and
   the banner's dismiss (28 pt) are below the ~44 pt touch guideline; acceptable for a pointer
   app, worth revisiting if this ever ships on iPad.
5. **VoiceOver.** The usage bar has a spoken summary; the rest relies on SwiftUI defaults and
   hasn't been audited.
6. **Heuristic accuracy.** Category and "similar model" detection are name- and
   metadata-based. They will be wrong sometimes, which is why both are labelled as guesses and
   are correctable.
