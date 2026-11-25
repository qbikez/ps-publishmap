function script:get-keyvaultSecret($vaultName, $secretName) {
    try {
        $secret = az keyvault secret show --vault-name $vaultName --name $secretName --query value -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $secret
        }
        else {
            Write-Warning "Failed to retrieve secret '$secretName' from vault '$vaultName'"
            return $null
        }
    }
    catch {
        Write-Warning "Error accessing Key Vault: $($_.Exception.Message)"
        return $null
    }
}
