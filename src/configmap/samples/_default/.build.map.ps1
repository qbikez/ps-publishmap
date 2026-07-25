$targets = @{
    _settings = @{ Concurrently = $false }
    
    "build"   = {
        param($ctx, [bool][switch]$noRestore)

        $a = @()
        if ($noRestore) {
            $a += "--no-restore"
        }
        dotnet build @a
    }
    "test"    = @{
        "concurrently" = @{
            "manual" = {
                invoke-concurrently -commands @{
                    "echo1" = "echo 'Hello, World eins!'"
                    "echo2" = "echo 'Hello, World zwei!'"
                }    
            }
            "auto"   = @{
                _settings = @{ Concurrently = $true }
                "echo1"   = { echo 'Hello, World eins!'; }
                "echo2"   = { echo 'Hello, World zwei!'; }
            }
        }
        "tmux"         = @{
            _settings = @{ TmuxAutoWindow = $true }
            "echo1"   = { echo 'Hello, World eins!'; }
            "echo2"   = { echo 'Hello, World zwei!'; }
        }
    }

    # NPM_SCRIPTS_PLACEHOLDER
}

return $targets