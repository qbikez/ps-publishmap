# Built-in get/set implementations for Entry._template types.
# appconfig and dotenv take an optional `userSecretsId` in the template: `user-secrets:{name}`
# option values are then read with `dotnet user-secrets --id`, so no project file is needed.
return [ordered]@{
    appconfig      = @{
        get = {
            param($ctx, $options, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            $id = (Get-ConfigEntryTemplate -Entry $_context.self).userSecretsId
            Find-ActiveAppConfigOption -File $file -Options $options -UserSecretsId $id
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'appconfig'
            $id = (Get-ConfigEntryTemplate -Entry $_context.self).userSecretsId
            Set-AppConfigOption -File $file -Values $value -UserSecretsId $id
        }
    }
    dotenv         = @{
        get = {
            param($ctx, $options, $_context)
            $template = Get-ConfigEntryTemplate -Entry $_context.self
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            $result = Find-ActiveEnvOption -File $file -Options $options -UserSecretsId $template.userSecretsId
            # Excluded keys still decide the active preset, but their values are never shown.
            $excluded = @($template.exclude | Where-Object { $_ })
            foreach ($key in @($result.Value.Keys)) {
                if ($excluded | Where-Object { $key -like $_ }) { $result.Value.Remove($key) }
            }
            $result
        }
        set = {
            param($ctx, $key, $value, $_context)
            $file = Get-ConfigEntryTemplateFile -Entry $_context.self -TypeName 'dotenv'
            $id = (Get-ConfigEntryTemplate -Entry $_context.self).userSecretsId
            Set-DotEnvOption -File $file -Values $value -UserSecretsId $id
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
