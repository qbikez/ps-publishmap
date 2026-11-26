# Lists the secrets of a project (`--project $dir`) or, when $Id is given, of a UserSecretsId
# (`--id $Id`, no project needed). Check $LASTEXITCODE for a failed listing.
function script:get-user-secrets($dir, [string]$Id) {
    $secrets = @{}

    try {
        $target = if ($Id) { @('--id', $Id) } else { @('--project', $dir) }
        $output = dotnet user-secrets list @target 2>&1
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

# How to name the secrets store in a dotnet command: `--id x` or `-p dir`.
function script:format-user-secrets-target($dir, [string]$Id) {
    if ($Id) { return "--id $Id" }
    return "-p $dir"
}
