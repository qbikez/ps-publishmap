[ordered]@{
    "api" = @{
        description = "API settings in .env (dotenv template)"
        _settings   = @{ process = "options" }
        _template   = "dotenv:.env"
        options     = [ordered]@{
            local = @{
                "API_URL" = "http://localhost:5000"
                "API_KEY" = "dev-key"
            }
            prod  = @{
                "API_URL" = "https://api.example.com"
                "API_KEY" = "prod-key"
            }
        }
    }
}
