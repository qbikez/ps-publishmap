$modules = [ordered]@{
    "storage" = @{
        description = "Appsettings storage endpoint (appconfig template)"
        _template   = @{
            type = "appconfig"
            file = "src/appsettings.Development.json"
        }
        options     = @{
            local = @{
                "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1"
            }
            prod  = @{
                "Storage:BaseUrl" = "https://prod.example"
            }
        }
    }
}

return $modules
