# Dotenv discovery sample: options and per-key entries come from the .env* files in this folder.
[ordered]@{
    # Presets only: .env.prod, .env.stg(.example) and .env.example become options.
    api_presets = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (presets from .env.* files)'
        _template   = 'dotenv:.env'
    }

    # Presets plus one entry per key in .env.example: api.API_URL, api.API_KEY, api.FLAG.
    api         = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings (presets and per-key entries)'
        _template   = @{ type = 'dotenv'; file = '.env'; keys = 'auto' }
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
