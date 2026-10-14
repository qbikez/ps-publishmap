BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1 -Force

    $script:localBaseUrl = 'https://127.0.0.1:10000/devstoreaccount1'
    $script:localAccount = 'devstore'
    $script:prodBaseUrl = 'https://prod.example'
    $script:prodAccount = 'prodstore'

    function script:Write-ConfigMapFile {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Body
        )

        $Body | Set-Content -LiteralPath $Path -Encoding utf8
    }

    function script:Read-AppSettings {
        param([Parameter(Mandatory)][string]$Path)
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
}

Describe 'qconf appconfig _template' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("appconfig-" + [guid]::NewGuid().ToString('n'))
        $script:projectDir = Join-Path $script:workDir 'project'
        New-Item -ItemType Directory -Path $script:projectDir -Force | Out-Null
        Push-Location $script:workDir

        $script:settingsFile = Join-Path $script:projectDir 'appsettings.Development.json'
        @{
            Storage = @{
                BaseUrl = $script:localBaseUrl
                Account = $script:localAccount
            }
        } | ConvertTo-Json | Set-Content -LiteralPath $script:settingsFile -Encoding utf8

        $script:mapFile = Join-Path $script:projectDir '.configuration.map.ps1'
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        description = 'Storage endpoint'
        options = @{
            local = @{
                'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                'Storage:Account' = 'devstore'
            }
            prod = @{
                'Storage:BaseUrl' = 'https://prod.example'
                'Storage:Account' = 'prodstore'
            }
        }
    }
    note = @{
        get = { 'from-note' }
        options = @{ a = 'A' }
    }
}
'@
    }

    AfterEach {
        Pop-Location
    }

    It 'reads the active preset from the appsettings file next to the map' {
        $result = qconf -map $script:mapFile storage -ErrorAction Stop

        $result.Path | Should -Be 'storage/'
        @($result.Active) | Should -Contain 'local'
        $result.Value['Storage:BaseUrl'] | Should -Be $script:localBaseUrl
        $result.Value['Storage:Account'] | Should -Be $script:localAccount
        Test-Path (Join-Path $script:workDir 'appsettings.Development.json') | Should -BeFalse
    }

    It 'reports no active preset when the file matches none' {
        @{
            Storage = @{
                BaseUrl = $script:localBaseUrl
                Account = 'other'
            }
        } | ConvertTo-Json | Set-Content -LiteralPath $script:settingsFile -Encoding utf8

        $result = qconf -map $script:mapFile storage -ErrorAction Stop

        $result.Active | Should -BeNullOrEmpty
        $result.Value['Storage:BaseUrl'] | Should -Be $script:localBaseUrl
        $result.Value['Storage:Account'] | Should -Be 'other'
    }

    It 'writes every key in the selected option into the file next to the map' {
        qconf -map $script:mapFile storage -value prod -ErrorAction Stop

        $settings = Read-AppSettings $script:settingsFile
        $settings.Storage.BaseUrl | Should -Be $script:prodBaseUrl
        $settings.Storage.Account | Should -Be $script:prodAccount
        Test-Path (Join-Path $script:workDir 'appsettings.Development.json') | Should -BeFalse

        $result = qconf -map $script:mapFile storage -ErrorAction Stop
        @($result.Active) | Should -Contain 'prod'
        $result.Value['Storage:BaseUrl'] | Should -Be $script:prodBaseUrl
        $result.Value['Storage:Account'] | Should -Be $script:prodAccount
    }

    It 'uses an explicit get instead of the appconfig template' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'missing.json'
        }
        get = { param($ctx, $options) 'custom-get' }
        options = @{
            local = @{ 'Storage:BaseUrl' = 'x' }
        }
    }
}
'@

        $result = qconf -map $script:mapFile storage -ErrorAction Stop

        $result.Value | Should -Be 'custom-get'
        Test-Path (Join-Path $script:projectDir 'missing.json') | Should -BeFalse
    }

    It 'uses an explicit set instead of the appconfig template' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        set = {
            param($ctx, $key, $value)
            'custom-set' | Set-Content 'custom-set.txt'
        }
        options = @{
            local = @{
                'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                'Storage:Account' = 'devstore'
            }
            prod = @{
                'Storage:BaseUrl' = 'https://prod.example'
                'Storage:Account' = 'prodstore'
            }
        }
    }
}
'@

        qconf -map $script:mapFile storage -value prod -ErrorAction Stop

        Get-Content (Join-Path $script:projectDir 'custom-set.txt') -Raw | Should -Match 'custom-set'
        $settings = Read-AppSettings $script:settingsFile
        $settings.Storage.BaseUrl | Should -Be $script:localBaseUrl
        $settings.Storage.Account | Should -Be $script:localAccount
    }

    It 'leaves an entry without a _template on its own get' {
        $result = qconf -map $script:mapFile note -ErrorAction Stop

        $result.Value | Should -Be 'from-note'
    }

    It 'does not expose _template as a command' {
        $map = Import-ConfigMap -Map $script:mapFile
        $entry = Get-MapEntry $map 'storage' -language conf
        $childNames = @((Get-CompletionList $entry -language conf).Keys)

        $childNames | Should -Not -Contain '_template'
        $childNames | Should -Not -Contain 'type'
        $childNames | Should -Not -Contain 'file'

        $words = @(qconf -map $script:mapFile '!complete' -Word '')
        $words | Should -Contain 'storage'
        $words | Should -Contain 'note'
        $words | Should -Not -Contain '_template'
        $words | Should -Not -Contain 'type'
        $words | Should -Not -Contain 'file'
    }

    It 'accepts options supplied by a scriptblock' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        options = {
            param($path)
            @{
                local = @{
                    'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                    'Storage:Account' = 'devstore'
                }
                prod = @{
                    'Storage:BaseUrl' = 'https://prod.example'
                    'Storage:Account' = 'prodstore'
                }
            }
        }
    }
}
'@

        $result = qconf -map $script:mapFile storage -ErrorAction Stop

        @($result.Active) | Should -Contain 'local'
        @($result.Options) | Should -Contain 'prod'
    }

    It 'runs an author-supplied validate script' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        validate = { param($path, $value, $key) $key -eq 'local' }
        options = @{
            local = @{
                'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                'Storage:Account' = 'devstore'
            }
            prod = @{
                'Storage:BaseUrl' = 'https://prod.example'
                'Storage:Account' = 'prodstore'
            }
        }
    }
}
'@

        $local = qconf -map $script:mapFile storage -ErrorAction Stop
        $local.IsValid | Should -BeTrue

        qconf -map $script:mapFile storage -value prod -ErrorAction Stop
        $prod = qconf -map $script:mapFile storage -ErrorAction Stop
        $prod.IsValid | Should -BeFalse
    }

    It 'gets and sets an appconfig _template entry through qbuild' {
        $buildMap = Join-Path $script:projectDir '.build.map.ps1'
        Write-ConfigMapFile $buildMap @'
[ordered]@{
    storage = [ordered]@{
        _settings   = @{ process = 'qconf' }
        description = 'Storage endpoint'
        _template   = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        options     = @{
            local = @{
                'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                'Storage:Account' = 'devstore'
            }
            prod = @{
                'Storage:BaseUrl' = 'https://prod.example'
                'Storage:Account' = 'prodstore'
            }
        }
    }
}
'@

        $result = qbuild -map $buildMap storage -ErrorAction Stop
        @($result.Active) | Should -Contain 'local'

        qbuild -map $buildMap storage -value prod -ErrorAction Stop
        $settings = Read-AppSettings $script:settingsFile
        $settings.Storage.BaseUrl | Should -Be $script:prodBaseUrl
        $settings.Storage.Account | Should -Be $script:prodAccount
    }

    It 'accepts the appsettings short-form _template string' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = 'appsettings:appsettings.Development.json'
        description = 'Storage endpoint'
        options = @{
            local = @{
                'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1'
                'Storage:Account' = 'devstore'
            }
            prod = @{
                'Storage:BaseUrl' = 'https://prod.example'
                'Storage:Account' = 'prodstore'
            }
        }
    }
}
'@

        $result = qconf -map $script:mapFile storage -ErrorAction Stop
        @($result.Active) | Should -Contain 'local'

        qconf -map $script:mapFile storage -value prod -ErrorAction Stop
        $settings = Read-AppSettings $script:settingsFile
        $settings.Storage.BaseUrl | Should -Be $script:prodBaseUrl
        $settings.Storage.Account | Should -Be $script:prodAccount
    }

    It 'rejects an unknown _template type' {
        Write-ConfigMapFile $script:mapFile @'
@{
    broken = @{
        _template = @{
            type = 'nope'
            file = 'appsettings.Development.json'
        }
        options = @{
            local = @{ 'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1' }
        }
    }
}
'@

        { qconf -map $script:mapFile broken -ErrorAction Stop } | Should -Throw "*type*nope*"
    }

    It 'rejects an unknown short-form _template' {
        Write-ConfigMapFile $script:mapFile @'
@{
    broken = @{
        _template = 'nope:appsettings.Development.json'
        options = @{
            local = @{ 'Storage:BaseUrl' = 'https://127.0.0.1:10000/devstoreaccount1' }
        }
    }
}
'@

        { qconf -map $script:mapFile broken -ErrorAction Stop } | Should -Throw "*template*nope*"
    }

    It 'rejects an unknown option key' {
        { qconf -map $script:mapFile storage -value nope -ErrorAction Stop } |
            Should -Throw '*option*nope*'
    }
}
