#!/usr/bin/env python3
"""Structural regression checks for Keymap's source-backed command catalog."""

import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
catalog = json.loads((ROOT / "command_library.json").read_text(encoding="utf-8"))
translations = json.loads((ROOT / "translations" / "en.json").read_text(encoding="utf-8"))
panel = (ROOT / "panel.luau").read_text(encoding="utf-8")
catalog_service = (ROOT / "catalog_service.luau").read_text(encoding="utf-8")
manifest = (ROOT / "plugin.toml").read_text(encoding="utf-8")

assert catalog["schema"] == 1
assert set(catalog["sources"]) == {"hyprland", "niri", "mangowc"}
assert all(catalog["sources"][source]["revision"] for source in catalog["sources"])

entries = catalog["entries"]
counts = Counter(entry["source"] for entry in entries)
assert counts == {"hyprland": 51, "niri": 135, "mangowc": 78}, counts

ids = [entry["id"] for entry in entries]
assert len(ids) == len(set(ids)), "command-library ids must be unique"
assert ids == sorted(ids, key=lambda entry_id: next(
    (item["source"], item["category"], item["id"])
    for item in entries if item["id"] == entry_id
)), "catalog ordering must remain deterministic"

category_translations = translations["panel"]["command_library"]["categories"]
for entry in entries:
    assert set(entry) == {"id", "source", "category", "kind", "template", "usage"}
    assert entry["id"].startswith(entry["source"] + "/")
    assert entry["category"] in category_translations
    assert entry["kind"] == ("shell" if entry["source"] == "noctalia" else "native")
    assert entry["template"].strip() == entry["template"] and entry["template"]
    assert not re.search(r"[\r\n\x00-\x1f]", entry["template"])
    assert entry["template"].count("{{") == entry["template"].count("}}")

by_id = {entry["id"]: entry for entry in entries}
for required_id in (
    "hyprland/window.close",
    "hyprland/workspace.swap_monitors",
    "niri/close-window",
    "niri/toggle-overview",
    "mangowc/killclient",
    "mangowc/reload_config",
):
    assert required_id in by_id, required_id

assert all(entry["source"] != "noctalia" for entry in entries), (
    "Noctalia/plugin commands must be discovered at runtime, never bundled"
)
assert all(entry["template"].startswith("hl.dsp.") and entry["template"].endswith(")")
           for entry in entries if entry["source"] == "hyprland")
assert all(";" not in entry["template"] and "{" not in re.sub(r"\{\{[^}]+\}\}", "", entry["template"])
           for entry in entries if entry["source"] == "niri")
assert all("#" not in entry["template"]
           for entry in entries if entry["source"] == "mangowc")

# Every matching command is available in the creator's single, panel-sized
# scroll viewport. The catalog itself must not create a nested wheel target.
# Plugin API 9 callbacks are closures; no stale global callback registry remains.
assert "local visibleCount = #matches" in panel
assert 'ui.column({ key = "command-library-results", gap = 3 }' in panel
assert 'elseif creatorOpen and viewMode == "list" then' in panel
assert 'body = ui.scroll({ flexGrow = 1 }, {' in panel
assert 'focus = true, flexGrow = 1, controlSize = "sm"' in panel
assert "local selectedEntry = entry" in panel
assert "onClick = useCallback" in panel
assert "local selectedSuggestion = suggestion" in panel
assert "onClick = useSuggestion" in panel
assert "finishDynamicCallbackRender()" not in panel
assert "registerDynamicCallback(" not in panel

# Noctalia commands come only from current IPC help, command manifests, and the
# live panel registry. This avoids hard-coding core or plugin commands.
assert 'local COMMAND_CATALOG_KEY = "keymap.runtime_command_catalog"' in panel
assert 'local COMMAND_CATALOG_REFRESH_KEY = "keymap.catalog_refresh_request"' in panel
assert "local function commandLibraryEntries()" in panel
assert 'enriched.origin = "compositor"' in panel
assert 'panel-toggle __keymap_catalog_probe__' in catalog_service
assert 'noctalia.state.set(COMMAND_CATALOG_REFRESH_KEY, current + 1)' in panel
assert 'creatorCommand = asString(value):gsub("%c+", " ")' in panel
assert "local function commandLibraryOriginIds()" in panel
assert "local function commandLibraryModuleRecords()" in panel
assert "local function commandSuggestions()" in panel
assert 'editDistance(second, "msg", 1)' in panel
assert 'ipcCommand("plugins commands")' in catalog_service
assert 'id = "catalog-service"' in manifest

print(f"command library tests: ok ({len(entries)} entries: {dict(counts)})")
