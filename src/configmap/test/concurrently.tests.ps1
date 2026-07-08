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

Describe "Test-ConcurrentlyEnabled" {
    BeforeEach {
        $script:concurrentlyBackup = $env:QCONF_CONCURRENTLY
        Remove-Item env:QCONF_CONCURRENTLY -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:concurrentlyBackup) {
            Remove-Item env:QCONF_CONCURRENTLY -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_CONCURRENTLY = $script:concurrentlyBackup
        }
    }

    It "is enabled when the env var is unset" {
        InModuleScope ConfigMap {
            Test-ConcurrentlyEnabled | Should -Be $true
        }
    }

    It "is disabled for falsy values" {
        foreach ($value in '0', 'false', 'no', 'off', 'FALSE', 'OFF') {
            $env:QCONF_CONCURRENTLY = $value
            InModuleScope ConfigMap {
                Test-ConcurrentlyEnabled | Should -Be $false
            }
        }
    }
}

Describe "qbuild concurrently" {
    BeforeEach {
        $script:concurrentlyBackup = $env:QCONF_CONCURRENTLY
        $script:capturedConcurrently = $null
        Remove-Item env:QCONF_CONCURRENTLY -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:concurrentlyBackup) {
            Remove-Item env:QCONF_CONCURRENTLY -ErrorAction SilentlyContinue
        }
        else {
            $env:QCONF_CONCURRENTLY = $script:concurrentlyBackup
        }

        InModuleScope ConfigMap {
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
                param($Commands, $Names)
                $script:capturedConcurrently = @{
                    Commands = $Commands
                    Names    = $Names
                }
            }
            Mock Invoke-EntryCommand

            qbuild -map $MapFile "build.all"

            $script:capturedConcurrently.Names | Should -Contain 'build.ui'
            $script:capturedConcurrently.Names | Should -Contain 'build.api'
            $script:capturedConcurrently.Commands.Count | Should -Be 2
            ($script:capturedConcurrently.Commands | Where-Object { $_ -match "build\.ui$" }).Count | Should -Be 1
            ($script:capturedConcurrently.Commands | Where-Object { $_ -match "build\.api$" }).Count | Should -Be 1
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
                param($Commands, $Names)
                $script:capturedConcurrently = @{
                    Commands = $Commands
                    Names    = $Names
                }
            }
            Mock Invoke-EntryCommand

            qbuild -map $MapFile "build.all" -NoRestore

            $script:capturedConcurrently.Commands[0] | Should -Match '-NoRestore'
            $script:capturedConcurrently.Commands[1] | Should -Match '-NoRestore'
        }
    }

    It "runs entry locally when QCONF_CONCURRENTLY is disabled" {
        $mapFile = Join-Path $TestDrive ".build.map.ps1"
        @'
@{
    "build" = @{
        "ui"  = { Write-Host "ui" }
        "api" = { Write-Host "api" }
    }
}
'@ | Set-Content $mapFile -Encoding utf8

        $env:QCONF_CONCURRENTLY = '0'

        InModuleScope ConfigMap -ArgumentList $mapFile {
            param($MapFile)
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
