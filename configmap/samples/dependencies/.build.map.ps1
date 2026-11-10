# Task dependencies: `qbuild pack` runs lint, restore, build, test, api.lint and api.build
# first, each once, then pack. See README.md.
[ordered]@{
    restore = @{
        description = 'Restore packages'
        exec        = { Write-Host 'restoring packages' }
    }
    lint    = @{
        description = 'Lint the sources'
        exec        = { Write-Host 'linting' }
    }
    build   = @{
        description = 'Build the solution'
        _dependsOn  = 'restore'
        exec        = { Write-Host 'building' }
    }
    test    = @{
        description = 'Run the tests'
        _dependsOn  = @('restore', 'build')
        exec        = { Write-Host 'running tests' }
    }
    api     = [ordered]@{
        lint  = @{
            description = 'Lint the API'
            exec        = { Write-Host 'linting api' }
        }
        build = @{
            description = 'Build the API'
            _dependsOn  = @('restore', './lint')
            exec        = { Write-Host 'building api' }
        }
    }
    pack    = @{
        description = 'Pack everything'
        _dependsOn  = @('lint', 'test', 'api.build')
        exec        = { Write-Host 'packing' }
    }
}
