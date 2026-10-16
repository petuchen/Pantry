# Naming

"Pantry" is a **working title**. Rename in one command: `scripts/rename-app.sh NewName`
(tested; it renames modules, folders, source, docs and the bundle script).

The app's job is *keep track of what's stored, see what's taking space, clear out what's
stale*. That is exactly what a pantry is for, which is why it leads the list. Good names here
are short, say "storage" without saying "AI", and are easy to type in Spotlight.

| Name | Idea | Watch out for |
|---|---|---|
| **Pantry** (working title) | Stock check, use what you have, clear out the old | Several unrelated recipe/food apps use it; check the Mac App Store before shipping |
| **Larder** | Same idea, more distinctive and a bit more "old-world" | Less immediately obvious to non-native English speakers |
| **Heft** | How much your models *weigh*; a pun on weights | Might read as "just a size tool", undersells the pull/cleanup features |
| **Stowage** | Where cargo is stored on a ship | Slightly nautical, harder to spell |
| **Stockroom** | The back room where inventory lives | Two words' worth of length; reads retail |
| **Cairn** | A stack of stones marking where you've been | Metaphor is about *trail marking*, not storage |
| **Tally** | Counting what you have | Heavily used already (forms, accounting) |
| **Quarry** | Where raw material is extracted | Sounds like "search"/"query", and a little industrial |
| **Hold** | A ship's hold, where cargo is kept | Too generic to search for |
| **Cellar** | Cool, dark place you keep things for later | **Avoid**: Homebrew's install folder is literally called the Cellar |

**My pick:** Pantry, with Larder as the backup if the store name is taken.

Bundle identifier is `dev.local.pantry` in `scripts/build-app.sh`; change it to your own
reverse-DNS before distributing.
