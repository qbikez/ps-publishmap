@{
    _settings = @{
    
    }
    frontend  = @{
        build = { 'build' }
    }
    api       = @{
        _settings = @{ process = 'options' }
        _template = 'dotenv:'
    }
}
