@{
    "init" = @{
        exec = {
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
        exec = {
            Write-Host "Restoring project dependencies..."
            & "scripts\lib\restore.ps1" "."
        }
        description = "Install required PowerShell modules and dependencies"
    }
    
    "build" = @{
        exec = {
            Write-Host "Building C# native components..."
            
            Push-Location
            try {
                Set-Location "src/publishmap.native/publishmap.core"
                dotnet build
                if ($LASTEXITCODE -ne 0) { 
                    throw "dotnet build failed" 
                }

                $libpath = "..\..\publishmap\lib"
                if (!(Test-Path $libpath)) { 
                    $null = New-Item -Type Directory $libpath
                }
                Copy-Item "bin\Debug\net451\*" $libpath -Force
                
                Write-Host "Build completed successfully"
            }
            finally {
                Pop-Location
            }
        }
        description = "Build the C# .NET components and copy to PowerShell module lib folder"
    }
    
    "test" = @{
        exec = {
            Write-Host "Running all tests..."
            
            # Ensure required modules are loaded
            Import-Module require -ErrorAction SilentlyContinue
            if (Get-Module require) {
                req process
            }
            
            # Run C# tests
            Push-Location
            try {
                Set-Location "src/publishmap.native/publishmap.test"
                dotnet test
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "C# tests failed"
                }
            }
            finally {
                Pop-Location
            }
            
            # Run PowerShell tests
            if ($env:APPVEYOR_JOB_ID -ne $null) {
                & "scripts/lib/test.appveyor.ps1"
            } else {
                & "scripts/lib/test.ps1"
            }
        }
        description = "Run both C# unit tests and PowerShell Pester tests"
    }
    
    "push" = @{
        exec = {
            param([switch]$NewVersion)
            
            Write-Host "Running push/publish workflow..."
            $args = @(".")
            if ($NewVersion) {
                $args += "-newversion"
            }
            & "scripts\lib\push.ps1" @args
        }
        description = "Push/publish module (runs tests first)"
    }
    
    "install" = @{
        exec = {
            Write-Host "Installing module locally..."
            & "scripts\lib\install.ps1" "."
        }
        description = "Install the PowerShell module locally"
    }
    
    "clean" = @{
        exec = {
            Write-Host "Cleaning build artifacts..."
            
            # Clean C# build outputs
            $paths = @(
                "src\publishmap.native\publishmap.core\bin",
                "src\publishmap.native\publishmap.core\obj",
                "src\publishmap.native\publishmap.test\bin", 
                "src\publishmap.native\publishmap.test\obj",
                "src\publishmap\lib"
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
        exec = {
            Write-Host "Performing clean rebuild..."
            
            # Clean first
            Invoke-EntryCommand (Get-MapEntry $script:BuildMap "clean") "exec"
            
            # Then build
            Invoke-EntryCommand (Get-MapEntry $script:BuildMap "build") "exec"
        }
        description = "Clean and rebuild the entire project"
    }
}