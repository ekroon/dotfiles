# Hammerspoon configuration

## Approved reloads

Hammerspoon watches `~/.hammerspoon` recursively, but draft edits and partial
chezmoi applies are inert. It reloads only when the deployed configuration
matches a complete approval chain:

- `reload-inventory` is the sorted, explicit list of runtime Lua files.
- `reload-manifest` contains the SHA-256 of each rendered runtime file in the
  exact inventory order.
- `reload-approval` pins the SHA-256 of the exact rendered manifest bytes.

All three formats are strict, LF-terminated, and versioned by their headers.
Runtime Lua symlinks, unmanaged Lua files, unsafe paths, duplicate entries,
missing files, malformed hashes, and inventory/manifest disagreement invalidate
the approval without disturbing the running configuration.

`approved_reload.lua` debounces filesystem events for 500 ms, verifies the full
chain, waits 250 ms, and verifies it again. It reloads only when both structured
snapshots and the event generation are unchanged and the approval identity is
new. The watcher and timers are retained on `hs.approvedReload`.

## Development workflow

1. Edit runtime files normally. They do not reload automatically.
2. Run the targeted checks while developing:

   ```bash
   mise x lua -- lua test/run.lua
   mise x lua -- luac -p init.lua approved_reload.lua kanata.lua Spoons/AppWindowCycler.spoon/init.lua test/*.lua
   ```

3. Review the finished changes, then explicitly approve their rendered bytes:

   ```bash
   hammerspoon-approve-reload
   ```

   The command locks against concurrent approval, validates the inventory,
   runs the tests, renders every runtime target once, syntax-checks and hashes
   those exact bytes, atomically replaces the manifest, and publishes the
   approval pin last.

4. Review `git diff` and deploy:

   ```bash
   chezmoi diff
   chezmoi apply ~/.hammerspoon
   ```

The initial migration to this mechanism requires one deliberate `hs.reload()`
after applying it because the previous watcher cannot understand these
artifacts. Subsequent approved applies reload automatically.

Manual Hammerspoon reloads or application restarts bypass this gate and load the
currently deployed files. Use them only deliberately for bootstrap or recovery.

## Maintaining runtime files

When adding, removing, or renaming a runtime Lua file, update
`reload-inventory` in bytewise sorted order. Do not hand-edit generated hashes
in `reload-manifest` or `reload-approval`; regenerate them with
`hammerspoon-approve-reload`.

Tests belong under `test/` and are intentionally excluded from the runtime
inventory. Keep parser and controller behavior in
`test/approved_reload_test.lua`; keep `test/init_test.lua` focused on wiring.
