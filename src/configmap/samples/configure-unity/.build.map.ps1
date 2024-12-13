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
            
            return "something"
            # return get-appsettingsobject -file "src/appsettings.Development.json" -options $options
        }
        set     = {
            param($ctx, $key, $value)

            Write-Host "set storage to '$key' ($value)"
            Write-Host "bound:"
            $bound = $PSBoundParameters
            $bound | ConvertTo-Json | write-host

            # set-appsettingsobject -file "src/appsettings.Development.json" -value $value
        }
    }

    "set" = {
        param($key, $value)

        if ($map -is [string]) {
            if (!(test-path $map)) {
                throw "map file '$map' not found"
            }
            $map = . $map
        }
        if (!$map) {
            throw "Failed to load map"
        }

        Write-Verbose "key=$key value=$value"

        $submodule = $map.$key
        if (!$submodule) {
            throw "module '$key' not found"
        }

        $optionKey = $value
        $options = Get-CompletionList $submodule -listKey "options"
        $optionValue = $options.$optionKey

        $bound = $PSBoundParameters
        $bound.key = $optionKey
        $bound.value = $optionValue
        
        Invoke-Set $submodule -ordered @("", $optionValue, $optionKey) -bound $bound
    }
    "get" = {
        param($submodule, [switch][bool] $validate)

        $options = Get-CompletionList $submodule -listKey "options"
                
        $bound = $PSBoundParameters
        $bound.options = $options
                
        $value = Invoke-Get $submodule -bound $bound
                
        $result = ConvertTo-MapResult $value $submodule $options
        $result | Write-Output
    }
}

return $modules
