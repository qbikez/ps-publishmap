#requires -version 7.0

# A steps check that calls qbuild with an entry switch.
# Try:
#   qbuild chk -typo      # warns that -typo is ignored: chk declares no such parameter
#   qbuild p.s -check     # expected: "[1/1] OK  s"; before the fix: "human mode" and MISSING

[ordered]@{
    chk = {
        param([switch]$porcelain)
        if ($porcelain) { [pscustomobject]@{ Ok = $true } }
        else { Write-Host 'human mode'; $null }
    }

    p   = [ordered]@{
        _settings = @{ process = 'steps' }
        s         = @{
            exec  = { Write-Host 'run' }
            check = { $r = qbuild chk -porcelain; return $r.Ok }
        }
    }
}
