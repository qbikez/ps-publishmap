# Task dependencies: `qbuild test` runs restore, then build (Release), then test.
[ordered]@{
    restore = @{
        description = 'Restore packages'
        exec        = { Write-Host 'restoring packages' }
    }
    build   = @{
        description = 'Build the solution'
        _dependsOn  = 'restore'
        exec        = {
            param([ValidateSet('Debug', 'Release')]$Configuration = 'Debug')
            Write-Host "building ($Configuration)"
        }
    }
    test    = @{
        description = 'Run the tests'
        _dependsOn  = @('restore', @{ entry = 'build'; args = @{ Configuration = 'Release' } })
        exec        = { Write-Host 'running tests' }
    }
    api     = [ordered]@{
        lint = { Write-Host 'linting api' }
        pack = @{
            description = 'Pack the API'
            _dependsOn  = @('./lint', 'test')
            exec        = { Write-Host 'packing api' }
        }
    }
}
