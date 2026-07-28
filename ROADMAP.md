# Noctalia Plugins Roadmap

## Keymap 1.4.0 — runtime command catalog

Status: paused on 2026-07-29.

### Saved work

- Community plugins branch: `feat/keymap-1.4`
- Runtime catalog commit: `532e24d`
- Hyprland CPU-budget fix carried forward from 1.3.4: `ed899af`
- Keymap manifest uses plugin API 9.
- The bundled command catalog now contains compositor-native actions only.
- `catalog_service.luau` discovers Noctalia core commands, enabled plugins, and
  registered panels at runtime.
- The command library supports origin, module, category, readiness, and fuzzy
  search filters.
- Plugin manifests and repository validation have preliminary support for
  declarative `[[command]]` entries.
- All Keymap 1.4 tests currently pass, as do 47 repository validator tests and
  validation of all 49 plugin manifests.

### Core dependency

The currently installed Noctalia v5 binary does not implement:

```text
noctalia msg plugins commands
```

It returns `unknown plugins subcommand 'commands'`. Keymap degrades gracefully:
core IPC commands and registered panels remain discoverable, but declared
plugin actions are unavailable.

Preliminary, uncommitted core support exists in:

```text
/home/blacku/dev/noctalia-core
```

It includes:

- parsing and validation of manifest `[[command]]` declarations;
- storage of declared commands in the plugin manifest model;
- JSON output from `noctalia msg plugins commands`;
- manifest and UI reconciler tests, which pass locally.

The core work currently shares a dirty `feat/plugin-panel-dnd` worktree with
other changes. It must be separated before opening a PR.

### Required before resuming

1. Move the Noctalia core command-manifest and IPC changes to a clean,
   dedicated branch based on current core `main`.
2. Add focused core tests for command JSON output, invalid fields, duplicate
   IDs, unknown entry references, and enabled-plugin filtering.
3. Submit and merge the core capability before relying on plugin command
   discovery in Keymap.
4. Add a Keymap regression for older Noctalia versions where
   `plugins commands` is unavailable.
5. Declare stable public actions in relevant plugin manifests, beginning with
   Audio Switcher:
   - `cycle-output`
   - `cycle-input`
   - `connect` with a slot payload

   Internal refresh and coordination events must remain undeclared.
6. Revisit command-library rendering before live deployment. The current 1.4
   code renders every matching entry at once; a large runtime catalog may
   exceed Noctalia's callback CPU budget. Add bounded rendering, pagination, or
   incremental result loading without reintroducing nested-scroll problems.
7. Build and run the updated Noctalia core, then test Keymap 1.4 live with:
   - a core-only catalog;
   - an older core without `plugins commands`;
   - community and official plugin declarations;
   - install/enable/disable changes while the panel is open;
   - large result sets and fuzzy queries;
   - Hyprland, Niri, and MangoWC create/edit flows.
8. Add a Keymap 1.4.0 changelog section and update documentation only after the
   runtime behavior and compatibility path are finalized.
9. Run the complete core and community-plugin test suites before opening the
   Keymap 1.4 PR.

### PR order

1. Noctalia core: manifest command schema and `plugins commands` IPC.
2. Community plugins: validator/documentation support and initial command
   declarations.
3. Keymap 1.4.0: runtime catalog UI and discovery service.
