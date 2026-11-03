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
}
