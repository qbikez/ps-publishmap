# Dotenv Discovery Sample

Shows how a `dotenv:` entry finds its own options from the `.env*` files next to it, in two ways.

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
```

Tab completion works for both: `qbuild api.<TAB>` lists `API_KEY API_URL FLAG`.

The sample modifies `.env`; restore it with `git checkout .env`.

## Rules

- `options` omitted: each `.env.<name>` is preset `<name>`; `.example`, `.sample` and `.template` suffixes are ignored; a bare `.env.example` is preset `example`.
- Explicit `options` in the map turn discovery off.
- `keys = 'auto'` reads `.env.example` (then `.sample`, `.template`); `keys = '<file>'` reads that file.
