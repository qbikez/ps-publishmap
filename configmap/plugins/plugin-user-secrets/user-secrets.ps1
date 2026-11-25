function script:get-user-secrets($dir) {
    $secrets = @{}

    try {
        $output = dotnet user-secrets list --project $dir 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $secrets
        }

        foreach ($line in $output) {
            if ($line -match "^(.+?)\s*=\s*(.*)$") {
                $secrets[$matches[1]] = $matches[2]
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve user secrets: $($_.Exception.Message)"
    }

    return $secrets
}
