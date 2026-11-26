# `user-secrets:{name}` option values, read from `dotnet user-secrets`. The implementation
# (user-secrets.ps1) is loaded lazily, the first time such a value is resolved.
# $Context.UserSecretsId (a template's `userSecretsId`) reads that store with `--id`;
# otherwise the project in $Context.Directory is used.
@{
    name           = 'user-secrets'
    description    = 'Resolve user-secrets:{name} option values from dotnet user-secrets'
    implementation = 'user-secrets.ps1'

    valuePrefixes  = @{
        'user-secrets:' = @{
            # Secrets: qconf masks the keys these fill when it prints a value.
            secret  = $true
            resolve = {
                param($Reference, $Context)

                $dir = $Context.Directory
                $id = $Context.UserSecretsId
                $target = format-user-secrets-target $dir -Id $id
                $secrets = $Context.Secrets
                if ($null -eq $secrets) {
                    $secrets = get-user-secrets $dir -Id $id
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "cannot set '$Reference': failed to list user secrets ($target). Do you have 'dotnet user-secrets' installed?"
                        return $null
                    }
                }
                if (!$secrets.ContainsKey($Reference)) {
                    Write-Warning "secret '$Reference' not found in user secrets. Please run 'dotnet user-secrets $target set $Reference <value>' to set the secret."
                    return $null
                }
                return $secrets[$Reference]
            }
        }
    }
}
