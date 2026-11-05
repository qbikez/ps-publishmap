# Built-in get/set implementations for Entry._template types.
return [ordered]@{
    appconfig      = @{
        get = {
            param($ctx, $options, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            Find-ActiveOption -file $file -options $options
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            Set-AppConfigOption -File $file -Values $value
        }
    }
    dotenv         = @{
        get = {
            param($ctx, $options, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            $result = Find-ActiveEnvOption -File $file -Options $options
            # Excluded keys still decide the active preset, but their values are never shown.
            $excluded = @((Get-ConfigEntryTemplate -Entry $_context.self).exclude | Where-Object { $_ })
            foreach ($key in @($result.Value.Keys)) {
                if ($excluded | Where-Object { $key -like $_ }) { $result.Value.Remove($key) }
            }
            $result
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            Set-DotEnvOption -File $file -Values $value
        }
    }
    'user-secrets' = @{
        # `list` must not read or print these values; only an explicit get/show does.
        sensitive = $true
        get       = {
            param($ctx, $options, $_context)
            $csproj = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'user-secrets'
            Find-ActiveSecretOption -Csproj $csproj -Options $options
        }
        set       = {
            param($ctx, $key, $value, $_context)
            $csproj = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'user-secrets'
            Set-UserSecretOption -Csproj $csproj -Values $value
        }
    }
}
