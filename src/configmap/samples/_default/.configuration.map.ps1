$modules = [ordered]@{
    "storage" = @{
        description = "Appsettings storage endpoint (appconfig template)"
        _template   = "appsettings:src/appsettings.Development.json"
        options     = @{
            local = @{
                "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1"
            }
            prod  = @{
                "Storage:BaseUrl" = "https://prod.example"
            }
        }
    }

    "api" = @{
        description = "API settings in .env (dotenv template)"
        _template   = "dotenv:.env"
        options     = @{
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

return $modules
