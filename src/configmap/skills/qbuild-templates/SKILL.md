---
name: qbuild-templates
description: >-
  Converts hand-written options get/set entries to built-in _template forms
  (appsettings / dotenv), including get/set overrides via $_context.base.
  Use when simplifying or modernizing .configuration.map.ps1 or config-process
  map entries, or when get/set only wrap appsettings JSON or .env helpers.
---

# qbuild templates

Built-in `_template` fills `get` / `set` for appsettings JSON and `.env` files. Prefer templates over hand-written helpers when the entry only reads/writes one of those files.

Load this recipe without installing:

```powershell
qbuild !agent.skills qbuild-templates
```

Install all ConfigMap skills (including this one):

```powershell
qbuild !agent.init [-Scope project|user] [-Agent cursor|claude|copilot]
```

## When to convert

Convert an entry when **all** of these hold:

- It is a config entry (`.configuration.map.ps1`, or `_settings.process = "config"` in a build/process map; legacy `process = "qconf"` still works).
- `get` / `set` only touch **one** fixed appsettings JSON file or **one** fixed `.env` file via helpers such as `get-appsettings*`, `set-appsettings*`, `Find-ActiveOption`, `get-envsetting*`, `set-envsetting*`, `get-envsettingsObject`, `set-envsettingsObject`.
- `options` values are hashtables of setting keys (`"Section:Key" = value`) or env vars (`ENV_VAR = value`), not bare scalars.

**Do not convert** when get/set do more than that file I/O (custom state files, opaque parameters, multi-file logic, scalar options, or intentional custom behavior) **unless** the extra work can sit in an override that still calls the template via `$_context.base` (see Overrides).

An author-supplied `get` or `set` always wins over the template fill-in. The template implementations are still stashed on `$_context.base` so overrides can call them.

## Locate entries

1. Prefer `.configuration.map.ps1` next to the project.
2. Also check `.build.map.ps1` / process maps for entries with `_settings = @{ process = "config" }` (or legacy `"qconf"`).
3. Work from the directory that owns the map (paths in `_template` are relative to the map’s directory / `_baseDir`).

## Convert

### Appsettings → `appsettings:` / `appconfig`

Prefer short form:

```powershell
"storage" = @{
    description = "Storage endpoint in appsettings JSON"
    _template   = "appsettings:src/appsettings.Development.json"
    options     = @{
        local = @{ "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1" }
        prod  = @{ "Storage:BaseUrl" = "https://prod.example" }
    }
}
```

Long form (equivalent): `_template = @{ type = "appconfig"; file = "src/appsettings.Development.json" }`.

Note: short prefix is `appsettings:`; long `type` is `appconfig`.

### Dotenv → `dotenv:`

```powershell
"api" = @{
    description = "API settings in .env"
    _template   = "dotenv:.env"
    options     = @{
        local = @{ "API_URL" = "http://localhost:5000"; "API_KEY" = "dev-key" }
        prod  = @{ "API_URL" = "https://api.example.com"; "API_KEY" = "prod-key" }
    }
}
```

Long form: `_template = @{ type = "dotenv"; file = ".env" }`.

### Keep / remove

- **Keep:** `description`, `options`, `validate`, `_settings`, `_dependsOn`.
- **Remove:** hand-written `get` / `set` when the template fully replaces them.
- **Keep as override:** a custom `get` / `set` that wraps the template (see Overrides).
- **Cleanup:** if a dotted `.config-utils.ps1` (or similar) exists only for those helpers and nothing else needs it, remove the unused dot-source after conversion.

### Before → after (appsettings)

Before:

```powershell
"storage" = @{
    options = @{
        local = @{ "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1" }
        prod  = @{ "Storage:BaseUrl" = "https://prod.example" }
    }
    get = {
        param($ctx, $options)
        Find-ActiveOption -file "src/appsettings.Development.json" -options $options
    }
    set = {
        param($ctx, $key, $value)
        set-appsettingsobject -file "src/appsettings.Development.json" -value $value
    }
}
```

After: use the appsettings `_template` example above (no `get` / `set`).

### Before → after (dotenv)

Before: get/set that only call `get-envsettingsObject` / `set-envsettingsObject` (or per-key env helpers) against one `.env` file, with hashtable options.

After: `_template = "dotenv:.env"` (or the matching path) and the same `options`; drop `get` / `set`.

## Overrides

Keep `_template` and supply your own `get` and/or `set` when you need extra work around the built-in file I/O. Author scriptblocks replace the filled-in commands; the template implementations remain available as:

| Call | Role |
|------|------|
| `& $_context.base.get $ctx $options $_context` | Inherited template get |
| `& $_context.base.set $ctx $key $value $_context` | Inherited template set |

Declare `$_context` in `param()` so the runtime can inject it. Call the base implementation when you still want the template’s read/write behavior.

### Override `set` (appsettings)

```powershell
"endpoint_override" = @{
    _settings   = @{ process = "config" }
    _template   = "appsettings:appsettings.Development.json"
    description = "Appsettings endpoint with post-set hook"
    options     = @{
        local = @{ "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1" }
        prod  = @{ "Storage:BaseUrl" = "https://storage.example" }
    }
    set = {
        param($ctx, $key, $value, $_context)
        & $_context.base.set $ctx $key $value $_context
        Write-Host "additional something"
    }
}
```

### Override `get`

```powershell
"storage" = @{
    _template = "appsettings:src/appsettings.Development.json"
    options   = @{
        local = @{ "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1" }
        prod  = @{ "Storage:BaseUrl" = "https://prod.example" }
    }
    get = {
        param($ctx, $options, $_context)
        $result = & $_context.base.get $ctx $options $_context
        # inspect / log / adjust $result, then return it
        $result
    }
}
```

### Rules

- Omit `get` / `set` entirely when the template alone is enough.
- Override only the side you customize; the other side still comes from `_template`.
- Replacing `set` without calling `$_context.base.set` skips writing the template file (by design — use that only when the override fully owns persistence).
- Same pattern works for `dotenv:` / `type = "dotenv"`.

See `samples/process-mixed` (`endpoint_override`) for a runnable example.

## Verify

From the map’s directory:

```powershell
# Prefer unified qbuild (config process in a build map)
qbuild <entry>
qbuild <entry> -value <option>
qbuild <entry> get
qbuild <entry> set <option>

# Standalone qconf (deprecated; still works for .configuration.map.ps1)
qconf get <entry>
qconf set <entry> <option>
```

Confirm option names still complete and values land in the expected JSON / `.env` file. For overrides, confirm both the template write/read and the extra side effects.
