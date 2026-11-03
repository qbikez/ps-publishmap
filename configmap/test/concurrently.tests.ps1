BeforeDiscovery {
    . "$PSScriptRoot\test-utils.ps1"
}
BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe "Format-QBuildCommand" {
    It "builds qbuild with entry and switch parameters" {
        InModuleScope ConfigMap {
            Format-QBuildCommand -mainCommand 'qbuild' -Entry 'build.ui' -BoundParameters @{ NoRestore = $true } -RemainingArguments @() |
                Should -Be 'qbuild build.ui -NoRestore'
        }
    }

    It "includes map path when map is a string" {
        InModuleScope ConfigMap {
            Format-QBuildCommand -mainCommand 'qbuild' -Entry 'build.ui' -BoundParameters @{ map = '.\.build.map.ps1' } -RemainingArguments @() |
                Should -Be "qbuild -map '.\.build.map.ps1' build.ui"
        }
    }

    It "appends passthrough arguments after --" {
        InModuleScope ConfigMap {
            Format-QBuildCommand -mainCommand 'qbuild' -Entry 'build.ui' -BoundParameters @{} -RemainingArguments @('--config=Release') |
                Should -Be 'qbuild build.ui -- --config=Release'
        }
    }
}

Describe "Test-ConcurrentlyAvailable" {
    It "returns false when npx is not available" {
        InModuleScope ConfigMap {
            Mock Get-Command { return $null }
            Test-ConcurrentlyAvailable | Should -Be $false
        }
    }

    It "returns false when concurrently is not available" {
        InModuleScope ConfigMap {
            Mock Get-Command { return [pscustomobject]@{ Name = 'npx' } }
            Mock Test-ConcurrentlyPackageAvailable { return $false }
            Test-ConcurrentlyAvailable | Should -Be $false
        }
    }

    It "returns true when npx and concurrently are available" {
        InModuleScope ConfigMap {
            Mock Get-Command { return [pscustomobject]@{ Name = 'npx' } }
            Mock Test-ConcurrentlyPackageAvailable { return $true }
            Test-ConcurrentlyAvailable | Should -Be $true
        }
    }

    It "falls back to local execution when npx is not available" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                throw 'concurrently should not run'
            }
            Mock Get-Command { return $null }
            Mock Write-Host
            Mock Get-TmuxInfo { return $null }

            qbuild -map $MapFile "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }

    It "falls back to local execution when concurrently package is missing" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                throw 'concurrently should not run'
            }
            Mock Get-Command { return [pscustomobject]@{ Name = 'npx' } }
            Mock Test-ConcurrentlyPackageAvailable { return $false }
            Mock Write-Host
            Mock Get-TmuxInfo { return $null }

            qbuild -map $MapFile "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }
}

Describe "Test-ConcurrentlyEnabled" {
    BeforeEach {
        $script:concurrentlyBackup = $env:QCONF_Concurrently
        Remove-Item env:QCONF_Concurrently -ErrorAction SilentlyContinue
        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    AfterEach {
        if ($null -eq $script:concurrentlyBackup) {
            Remove-Item env:QCONF_Concurrently -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_Concurrently = $script:concurrentlyBackup
        }

        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    It "is disabled when the env var is unset" {
        InModuleScope ConfigMap {
            Test-ConcurrentlyEnabled | Should -Be $false
        }
    }

    It "is disabled for falsy values" {
        foreach ($value in '0', 'false', 'no', 'off', 'FALSE', 'OFF') {
            $env:QCONF_Concurrently = $value
            InModuleScope ConfigMap {
                Update-ConfigMapSettings | Out-Null
                Test-ConcurrentlyEnabled | Should -Be $false
            }
        }
    }
}

Describe "qbuild concurrently" {
    BeforeEach {
        $script:concurrentlyBackup = $env:QCONF_Concurrently
        $script:capturedConcurrently = $null
        $env:QCONF_Concurrently = '1'
        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
        }
    }

    AfterEach {
        if ($null -eq $script:concurrentlyBackup) {
            Remove-Item env:QCONF_Concurrently -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_Concurrently = $script:concurrentlyBackup
        }

        InModuleScope ConfigMap {
            Update-ConfigMapSettings | Out-Null
            $script:ConfigMapConcurrentlyInvoker = $null
        }
    }

    It "runs virtual build.all sequentially when map is an in-memory hashtable" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "build" = @{
                    "ui"  = { Write-Host "ui" }
                    "api" = { Write-Host "api" }
                }
            }

            qbuild -map $targets "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }

    It "runs explicit build.all locally" {
        InModuleScope ConfigMap {
            Mock Write-Host
            $targets = @{
                "build" = @{
                    "ui"  = { Write-Host "ui" }
                    "all" = { Write-Host "custom all" }
                }
            }

            qbuild -map $targets "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "custom all" }
            Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -eq "ui" }
        }
    }

    It "delegates virtual build.all to concurrently when using a map file" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                param($Commands)
                $script:capturedConcurrently = $Commands
            }
            Mock Invoke-EntryCommand
            Mock Get-TmuxInfo { return $null }
            Mock Test-ConcurrentlyAvailable { return $true }

            qbuild -map $MapFile "build.all"

            $script:capturedConcurrently.Keys | Should -Contain 'build.ui'
            $script:capturedConcurrently.Keys | Should -Contain 'build.api'
            $script:capturedConcurrently.Count | Should -Be 2
            $script:capturedConcurrently['build.ui'] | Should -Match "build\.ui$"
            $script:capturedConcurrently['build.api'] | Should -Match "build\.api$"
            Should -Invoke Invoke-EntryCommand -Times 0 -Exactly
        }
    }

    It "prefers tmux over concurrently for build.all when inside tmux" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "_settings" = @{ "TmuxAutoWindow" = $true }
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                throw 'concurrently should not run when tmux handles build.all'
            }
            Mock Write-Host
            Mock Invoke-EntryCommand
            Mock Invoke-TmuxCommand
            Mock Get-TmuxInfo { return [pscustomobject]@{ sessionName = 'dev'; windowName = 'shell' } }

            qbuild -map $MapFile "build.all"

            Should -Invoke Invoke-TmuxCommand -Times 2 -Exactly
            Should -Invoke Invoke-EntryCommand -Times 0 -Exactly
        }
    }

    It "passes qbuild arguments in concurrently child commands" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            $script:ConfigMapConcurrentlyInvoker = {
                param($Commands)
                $script:capturedConcurrently = $Commands
            }
            Mock Invoke-EntryCommand
            Mock Get-TmuxInfo { return $null }
            Mock Test-ConcurrentlyAvailable { return $true }

            qbuild -map $MapFile "build.all" -NoRestore

            $script:capturedConcurrently.Count | Should -Be 2
            foreach ($command in $script:capturedConcurrently.Values) {
                $command | Should -Match '-NoRestore'
            }
        }
    }

    It "runs entry locally when QCONF_Concurrently is disabled" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        $env:QCONF_Concurrently = '0'

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
            Update-ConfigMapSettings | Out-Null
            $script:ConfigMapConcurrentlyInvoker = {
                throw 'concurrently should not run'
            }
            Mock Write-Host
            Mock Get-TmuxInfo { return $null }

            qbuild -map $MapFile "build.all"

            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "ui" }
            Should -Invoke Write-Host -Exactly 1 -ParameterFilter { $Object -eq "api" }
        }
    }
}
