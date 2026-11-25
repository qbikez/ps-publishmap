# `user-secrets:{name}` option values, read from `dotnet user-secrets`. The implementation
# (user-secrets.ps1) is loaded lazily, the first time such a value is resolved.
@{
    name           = 'user-secrets'
    description    = 'Resolve user-secrets:{name} option values from dotnet user-secrets'
    implementation = 'user-secrets.ps1'

    valuePrefixes  = @{
        'user-secrets:' = @{
            resolve = {
                param($Reference, $Context)

                $dir = $Context.Directory
                $secrets = $Context.Secrets
                if ($null -eq $secrets) {
                    $secrets = get-user-secrets $dir
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "cannot set '$Reference': failed to list user secrets for project in '$dir'. Do you have 'dotnet user-secrets' installed?"
                        return $null
                    }
                }
                if (!$secrets.ContainsKey($Reference)) {
                    Write-Warning "secret '$Reference' not found in user secrets. Please run 'dotnet user-secrets -p $dir set $Reference <value>' to set the secret."
                    return $null
                }
                return $secrets[$Reference]
            }
        }
    }
}
