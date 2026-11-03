@{
    "init"    = @{
        exec        = {
            Write-Host "Initializing repository dependencies..."
            
            # Update git submodules
            if (Test-Path ".git") {
                Write-Host "Updating git submodules..."
                git submodule update --init --recursive
            }
            
            # Run the init script
            & "scripts\lib\init.ps1" "."
        }
        description = "Initialize git submodules and PowerShell dependencies"
    }
    
    "restore" = @{
        exec        = {
            Write-Host "Restoring project dependencies..."
            & "scripts\lib\restore.ps1" "."
        }
        description = "Install required PowerShell modules and dependencies"
    }
    
    "build"   = @{
        exec        = {
            Write-Host "Building C# native components..."
            
            Push-Location
            try {
                Set-Location "publishmap.native"
                dotnet build publishmap.native.sln
                if ($LASTEXITCODE -ne 0) { 
                    throw "dotnet build failed" 
                }

                $libpath = "..\publishmap\lib"
                if (!(Test-Path $libpath)) { 
                    $null = New-Item -Type Directory $libpath
                }
                Copy-Item "publishmap.core\bin\Debug\netstandard2.0\*" $libpath -Force
                
                Write-Host "Build completed successfully"
            }
            finally {
                Pop-Location
            }
        }
        description = "Build the C# .NET components and copy to PowerShell module lib folder"
    }
    
    "test"    = @{
        exec        = {
            Write-Host "Running all tests..."
            
            # Ensure required modules are loaded
            Import-Module require -ErrorAction SilentlyContinue
            if (Get-Module require) {
                req process
            }
            
            # Run C# tests
            Push-Location
            try {
                Set-Location "publishmap.native"
                dotnet test publishmap.test/publishmap.test.csproj 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "C# tests failed"
                }
            }
            finally {
                Pop-Location
            }
            
            # Run PowerShell tests
            $publishmapRoot = Join-Path $PSScriptRoot "publishmap"
            if ($env:APPVEYOR_JOB_ID -ne $null) {
                & "scripts/lib/test.appveyor.ps1" $publishmapRoot
            }
            else {
                & "scripts/lib/test.ps1" $publishmapRoot
            }
        }
        description = "Run both C# unit tests and PowerShell Pester tests"
    }
    
    "lint"    = @{
        exec        = {
            param([switch]$Fix)

            if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
                throw "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser"
            }
            Import-Module PSScriptAnalyzer

            # Formatting rules only: Invoke-Formatter would otherwise also apply fixing rules such as
            # alias expansion, which changes behavior (e.g. `qbuild` vs `Invoke-QBuild` invocation name).
            $allSettings = Import-PowerShellDataFile (Join-Path $PSScriptRoot "PSScriptAnalyzerSettings.psd1")
            $formatRules = @('PSUseConsistentIndentation', 'PSUseConsistentWhitespace', 'PSAlignAssignmentStatement')
            $settings = @{
                IncludeRules = $formatRules
                Rules        = @{}
            }
            foreach ($rule in $formatRules) { $settings.Rules[$rule] = $allSettings.Rules[$rule] }
            # git ls-files skips untracked build output and submodule content (scripts/lib)
            $files = @(git -C $PSScriptRoot ls-files "*.ps1" "*.psm1" | Where-Object { $_ -notmatch '(^|/)lib/' })

            $unformatted = @()
            foreach ($file in $files) {
                $path = Join-Path $PSScriptRoot $file
                $bytes = [IO.File]::ReadAllBytes($path)
                $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
                $content = [IO.File]::ReadAllText($path)
                $formatted = Invoke-Formatter -ScriptDefinition $content -Settings $settings
                if ($formatted -ceq $content) { continue }

                $unformatted += $file
                if ($Fix) {
                    [IO.File]::WriteAllText($path, $formatted, [Text.UTF8Encoding]::new($hasBom))
                }
            }

            if ($Fix) {
                Write-Host "Formatted $($unformatted.Count) of $($files.Count) file(s)"
                return
            }
            if ($unformatted.Count -gt 0) {
                $unformatted | ForEach-Object { Write-Host "  needs formatting: $_" -ForegroundColor Yellow }
                throw "$($unformatted.Count) file(s) need formatting. Run: qbuild lint -Fix"
            }
            Write-Host "Lint passed ($($files.Count) file(s) checked)"
        }
        description = "Check PowerShell formatting with PSScriptAnalyzer (use -Fix to apply formatting)"
    }

    "push"    = @{
        exec        = {
            param([string]$path = $null, [switch]$NewVersion)
            
            Write-Host "Running push/publish workflow..."
            $a = @{
                Verbose    = $true
                path       = $path ? $path : "."
                newversion = $NewVersion
            }
            
            & "$psscriptroot\scripts\lib\push.ps1" @a
        }
        description = "Push/publish module (runs tests first)"
    }
    
    "install" = @{
        exec        = {
            Write-Host "Installing module locally..."
            & "scripts\lib\install.ps1" "."
        }
        description = "Install the PowerShell module locally"
    }
    
    "clean"   = @{
        exec        = {
            Write-Host "Cleaning build artifacts..."
            
            # Clean C# build outputs
            $paths = @(
                "publishmap.native\publishmap.core\bin",
                "publishmap.native\publishmap.core\obj",
                "publishmap.native\publishmap.test\bin", 
                "publishmap.native\publishmap.test\obj",
                "publishmap\lib"
            )
            
            foreach ($path in $paths) {
                if (Test-Path $path) {
                    Write-Host "Removing $path"
                    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Host "Clean completed"
        }
        description = "Remove build artifacts and compiled binaries"
    }
    
    "rebuild" = @{
        exec        = {
            Write-Host "Performing clean rebuild..."
            
            # Clean first
            Invoke-EntryCommand (Get-MapEntry $script:BuildMap "clean") "exec"
            
            # Then build
            Invoke-EntryCommand (Get-MapEntry $script:BuildMap "build") "exec"
        }
        description = "Clean and rebuild the entire project"
    }
}