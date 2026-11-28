# Dotenv Discovery Sample

Shows how a `dotenv:` entry finds its own options and per-key entries from the `.env*` files next to it, and how to override the template's get/set.

## Files

| File | Role |
|---|---|
| `.env` | The active config. `qbuild` reads and writes it. |
| `.env.example` | Every key, with `#` comments as descriptions. Source for per-key entries. |
| `.env.prod` | Preset `prod` |
| `.env.stg`, `.env.stg.example` | Preset `stg` (the real file wins over the example) |

## Try it

```powershell
Import-Module ..\..\configmap.psm1
cd .\samples\dotenv

# 1. Presets: sibling files become options
qbuild api_presets -porcelain      # Options: prod, stg, example
qbuild api -value prod             # .env now holds .env.prod's keys

# 2. Per-key entries: one entry per key in .env.example
qbuild api.API_URL                 # show the current value
qbuild api.API_URL -value https://staging.example.com   # change only that key
qbuild api.FLAG -value off         # adds FLAG to .env if it was missing
qbuild api.API_URL -value not-a-url   # fails: the map's own API_URL entry replaces the generated one and validates

# 3. Excluded keys: api_safe skips API_KEY, so there is no api_safe.API_KEY entry
qbuild api_safe.API_URL            # works; qbuild api_safe.API_KEY does not exist

# 4. Hand-written sub-entries (api_manual): each key has its own get/set in the map
qbuild api_manual.API_URL set https://manual.example.com

# 5. get/set overrides (api_hooks): wrap the template's get/set through $_context.base
qbuild api_hooks -value stg        # writes .env as usual, then prints the post-set message
qbuild api_hooks -Verbose          # the get override logs the active preset
```

Tab completion works for both: `qbuild api.<TAB>` lists `API_KEY API_URL FLAG`.

The sample modifies `.env`; restore it with `git checkout .env`.

## Rules

- `options` omitted: each `.env.<name>` is preset `<name>`; `.example`, `.sample` and `.template` suffixes are ignored; a bare `.env.example` is preset `example`.
- Explicit `options` in the map turn discovery off.
- `keys = 'auto'` reads `.env.example` (then `.sample`, `.template`); `keys = '<file>'` reads that file.
- `exclude = @('API_KEY', 'SECRET_*')` (string or array, `-like` wildcards) removes those keys from the per-key entries; they are not listed, completed or readable through the child entries, and the parent entry's value leaves them out.
- A key the map already defines as a child entry is not generated, so a hand-written child (`api.API_URL`) overrides just that key.
- An entry's own `get` / `set` replace the template's; the template versions remain on `$_context.base.get` / `$_context.base.set`. They apply to the entry (preset switching), not to the generated per-key children.
