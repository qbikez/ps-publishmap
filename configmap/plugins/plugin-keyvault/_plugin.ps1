# Azure Key Vault `keyvault:{vault}/{secret}` option values, read with the Azure CLI. The
# implementation (keyvault.ps1) is loaded lazily, the first time such a value is resolved.
@{
    name           = 'keyvault'
    description    = 'Resolve keyvault:{vault}/{secret} option values from Azure Key Vault'
    implementation = 'keyvault.ps1'

    valuePrefixes  = @{
        'keyvault:' = @{
            secret  = $true
            resolve = {
                param($Reference)
                $splits = $Reference.Split('/')
                get-keyvaultSecret $splits[0] $splits[1]
            }
        }
    }
}
