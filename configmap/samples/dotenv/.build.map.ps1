# Dotenv discovery sample: options and per-key entries come from the .env* files in this folder.
[ordered]@{
    # Presets only: .env.prod, .env.stg(.example) and .env.example become options.
    api_presets = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (presets from .env.* files)'
        _template   = 'dotenv:.env'
    }

    # Presets plus one entry per key in .env.example: api.API_URL, api.API_KEY, api.FLAG.
    # A key the map already defines is not generated, so the API_URL below replaces the
    # discovered api.API_URL; api.API_KEY and api.FLAG are still generated.
    api         = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (presets and per-key entries)'
        _template   = @{ type = 'dotenv'; file = '.env'; keys = 'auto' }
        API_URL     = [ordered]@{
            description = 'Base URL of the backend (must be http or https)'
            get         = {
                param($ctx, $options, $_context)
                get-envsetting 'API_URL' (Join-Path $_context.self._baseDir '.env')
            }
            set         = {
                param($ctx, $key, $value, $_context)
                if ($key -notmatch '^https?://') { throw "API_URL must be an http(s) URL, got '$key'" }
                set-envsetting 'API_URL' $key (Join-Path $_context.self._baseDir '.env')
            }
        }
    }

    # Same template with get and set overridden on the entry itself. The template's own
    # get/set stay on $_context.base, so the overrides wrap them instead of reimplementing
    # the .env I/O. The generated per-key children (api_hooks.API_URL, ...) keep their
    # built-in get/set; these overrides apply only when switching presets.
    api_hooks   = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (get/set overrides around the template)'
        _template   = @{ type = 'dotenv'; file = '.env'; keys = 'auto' }
        get         = {
            param($ctx, $options, $_context)
            $result = & $_context.base.get $ctx $options $_context
            Write-Verbose "api_hooks: active preset is '$($result.Active)'"
            $result
        }
        set         = {
            param($ctx, $key, $value, $_context)
            & $_context.base.set $ctx $key $value $_context
            Write-Host "api_hooks: switched to key='$key' value=$($value | ConvertTo-Json -Depth 10); restart the API to pick it up"
        }
    }

    # Same as api, but exclude keeps API_KEY (and anything matching SECRET_*) out of the per-key entries:
    # only api_safe.API_URL and api_safe.FLAG exist, so the secret never shows up in list or completion.
    api_safe    = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (per-key entries without secrets)'
        _template   = @{ type = 'dotenv'; file = '.env'; keys = 'auto'; exclude = @('API_KEY', 'SECRET_*') }
    }

    # Hand-written sub-entries, no _template: each one gets and sets a single key in .env.
    api_manual  = [ordered]@{
        description = 'API settings (manually configured keys)'
        API_URL     = [ordered]@{
            _settings   = @{ process = 'options' }
            description = 'Base URL of the backend'
            get         = {
                param($ctx, $options, $_context)
                get-envsetting 'API_URL' (Join-Path $_context.self._baseDir '.env')
            }
            set         = {
                param($ctx, $key, $value, $_context)
                set-envsetting 'API_URL' $key (Join-Path $_context.self._baseDir '.env')
            }
        }
        API_KEY     = [ordered]@{
            _settings   = @{ process = 'options' }
            description = 'Secret used to sign requests'
            get         = {
                param($ctx, $options, $_context)
                get-envsetting 'API_KEY' (Join-Path $_context.self._baseDir '.env')
            }
            set         = {
                param($ctx, $key, $value, $_context)
                set-envsetting 'API_KEY' $key (Join-Path $_context.self._baseDir '.env')
            }
        }
    }
}
