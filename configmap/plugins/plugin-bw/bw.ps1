# Per-process cache: `bw` takes about a second per call and maps often repeat an item.
$script:bwSecretCache = @{}

function script:get-bwSecret($item, $field) {
    $cacheKey = "$item/$field"
    if ($script:bwSecretCache.ContainsKey($cacheKey)) { return $script:bwSecretCache[$cacheKey] }

    if (!(Get-Command bw -ErrorAction SilentlyContinue)) {
        Write-Warning "Cannot read '$item' from Bitwarden: the 'bw' CLI was not found on PATH."
        return $null
    }

    $builtIn = @{ '' = 'password'; 'password' = 'password'; 'username' = 'username'; 'totp' = 'totp'; 'uri' = 'uri'; 'notes' = 'notes' }
    $builtInName = $builtIn["$field"]

    try {
        # Output is captured, never forwarded, so the secret cannot leak into warnings.
        if ($builtInName) {
            $secret = bw get $builtInName $item --nointeraction 2>$null
        }
        else {
            $json = bw get item $item --nointeraction 2>$null
        }
        $failed = $LASTEXITCODE -ne 0
    }
    catch {
        Write-Warning "Error accessing Bitwarden: $($_.Exception.Message)"
        return $null
    }

    if ($failed) {
        Write-Warning "Failed to read '$item' from Bitwarden. The item may not exist or the vault is locked: run 'bw unlock' and set BW_SESSION."
        return $null
    }

    if (!$builtInName) {
        $match = @(($json | ConvertFrom-Json).fields | Where-Object { $_.name -eq $field })
        if ($match.Count -eq 0) {
            Write-Warning "Bitwarden item '$item' has no custom field '$field'."
            return $null
        }
        $secret = $match[0].value
    }

    $script:bwSecretCache[$cacheKey] = $secret
    return $secret
}
