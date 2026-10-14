$modules = [ordered]@{
    "storage" = @{
        description = "Storage endpoint in appsettings JSON"
        type        = "appconfig"
        file        = "src/appsettings.Development.json"
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
