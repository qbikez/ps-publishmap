. "$PSScriptRoot/.config-utils.ps1"

$modules = [ordered]@{
    "storage" = @{
        options = {
            param($path)
            return @{
                local = @{
                    "Storage:BaseUrl" = "https://127.0.0.1:10000/devstoreaccount1"
                }
            }
        }
        get     = {
            param($ctx, $options)
            
            return get-appsettingsobject -file "src/appsettings.Development.json" -options $options
        }
        set     = {
            param($ctx, $key, $value)

            Write-Host "set storage to '$key' ($value)"
            $bound = $PSBoundParameters
            $bound | ConvertTo-Json | write-host

            set-appsettingsobject -file "src/appsettings.Development.json" -value $value
        }
    }
}

return $modules
