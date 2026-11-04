@{
    "build.incremental" = @{
        _settings = @{
            process    = "steps"
            forceCheck = $true
            useWorkDir = $true
        }

        project   = @{
            check = { 
                $ts = cat ".timestamp"
                $ts = [datetime]::Parse($ts)

                $diff = [datetime]::UtcNow - $ts

                Write-Host "diff = $diff"

                return $diff -lt [timespan]::FromSeconds(5)
            }
            exec  = {
                Write-Host "Building the project"
                cat "project.csproj"
                [datetime]::UtcNow > ".timestamp"
            }
        }
    }
}