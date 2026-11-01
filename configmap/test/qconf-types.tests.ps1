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

    function script:Write-DotEnvFile {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][hashtable]$Values
        )

        $lines = foreach ($key in @($Values.Keys)) {
            "$key=$($Values[$key])"
        }
        $lines | Set-Content -LiteralPath $Path -Encoding utf8
    }

    function script:Read-DotEnvFile {
        param([Parameter(Mandatory)][string]$Path)
        $result = [ordered]@{}
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^([^=]+)=(.*)$') {
                $result[$Matches[1].Trim()] = $Matches[2].Trim('"')
            }
        }
        return $result
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
        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop

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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop

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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop
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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop

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

    It 'lets an overridden set call the inherited template set via $_context.base' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        set = {
            param($ctx, $key, $value, $_context)
            & $_context.base.set $ctx $key $value $_context
            'wrapped-set' | Set-Content 'wrapped-set.txt'
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

        Get-Content (Join-Path $script:projectDir 'wrapped-set.txt') -Raw | Should -Match 'wrapped-set'
        $settings = Read-AppSettings $script:settingsFile
        $settings.Storage.BaseUrl | Should -Be $script:prodBaseUrl
        $settings.Storage.Account | Should -Be $script:prodAccount
    }

    It 'lets an overridden get call the inherited template get via $_context.base' {
        Write-ConfigMapFile $script:mapFile @'
@{
    storage = @{
        _template = @{
            type = 'appconfig'
            file = 'appsettings.Development.json'
        }
        get = {
            param($ctx, $options, $_context)
            $result = & $_context.base.get $ctx $options $_context
            'wrapped-get' | Set-Content 'wrapped-get.txt'
            $result
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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop

        Get-Content (Join-Path $script:projectDir 'wrapped-get.txt') -Raw | Should -Match 'wrapped-get'
        @($result.Active) | Should -Contain 'local'
        $result.Value['Storage:BaseUrl'] | Should -Be $script:localBaseUrl
    }

    It 'leaves an entry without a _template on its own get' {
        $result = qconf -map $script:mapFile note -porcelain -ErrorAction Stop

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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop

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

        $local = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop
        $local.IsValid | Should -BeTrue

        qconf -map $script:mapFile storage -value prod -ErrorAction Stop
        $prod = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop
        $prod.IsValid | Should -BeFalse
    }

    It 'gets and sets an appconfig _template entry through qbuild' {
        $buildMap = Join-Path $script:projectDir '.build.map.ps1'
        Write-ConfigMapFile $buildMap @'
[ordered]@{
    storage = [ordered]@{
        _settings   = @{ process = 'options' }
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

        $result = qbuild -map $buildMap storage -porcelain -ErrorAction Stop
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

        $result = qconf -map $script:mapFile storage -porcelain -ErrorAction Stop
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

Describe 'qconf dotenv _template' {
    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("dotenv-" + [guid]::NewGuid().ToString('n'))
        $script:projectDir = Join-Path $script:workDir 'project'
        New-Item -ItemType Directory -Path $script:projectDir -Force | Out-Null
        Push-Location $script:workDir

        $script:localApiUrl = 'http://localhost:5000'
        $script:localApiKey = 'dev-key'
        $script:prodApiUrl = 'https://api.example.com'
        $script:prodApiKey = 'prod-key'

        $script:envFile = Join-Path $script:projectDir '.env'
        Write-DotEnvFile $script:envFile @{
            API_URL = $script:localApiUrl
            API_KEY = $script:localApiKey
        }

        $script:mapFile = Join-Path $script:projectDir '.configuration.map.ps1'
        Write-ConfigMapFile $script:mapFile @'
@{
    api = @{
        _template = @{
            type = 'dotenv'
            file = '.env'
        }
        description = 'API settings'
        options = @{
            local = @{
                API_URL = 'http://localhost:5000'
                API_KEY = 'dev-key'
            }
            prod = @{
                API_URL = 'https://api.example.com'
                API_KEY = 'prod-key'
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

    It 'reads the active preset from the .env file next to the map' {
        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop

        $result.Path | Should -Be 'api/'
        @($result.Active) | Should -Contain 'local'
        $result.Value['API_URL'] | Should -Be $script:localApiUrl
        $result.Value['API_KEY'] | Should -Be $script:localApiKey
        Test-Path (Join-Path $script:workDir '.env') | Should -BeFalse
    }

    It 'reports no active preset when the file matches none' {
        Write-DotEnvFile $script:envFile @{
            API_URL = $script:localApiUrl
            API_KEY = 'other'
        }

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop

        $result.Active | Should -BeNullOrEmpty
        $result.Value['API_URL'] | Should -Be $script:localApiUrl
        $result.Value['API_KEY'] | Should -Be 'other'
    }

    It 'writes every key in the selected option into the .env file next to the map' {
        qconf -map $script:mapFile api -value prod -ErrorAction Stop

        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:prodApiUrl
        $envValues['API_KEY'] | Should -Be $script:prodApiKey
        Test-Path (Join-Path $script:workDir '.env') | Should -BeFalse

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'prod'
        $result.Value['API_URL'] | Should -Be $script:prodApiUrl
        $result.Value['API_KEY'] | Should -Be $script:prodApiKey
    }

    It 'preserves unrelated .env keys when setting an option' {
        Write-DotEnvFile $script:envFile @{
            API_URL = $script:localApiUrl
            API_KEY = $script:localApiKey
            OTHER   = 'keep-me'
        }

        qconf -map $script:mapFile api -value prod -ErrorAction Stop

        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:prodApiUrl
        $envValues['API_KEY'] | Should -Be $script:prodApiKey
        $envValues['OTHER'] | Should -Be 'keep-me'
    }

    It 'replaces a value in a one-line .env file' {
        Set-Content -LiteralPath $script:envFile -Value 'API_URL=http://localhost:5000' -NoNewline -Encoding utf8

        qconf -map $script:mapFile api -value prod -ErrorAction Stop

        $lines = @(Get-Content -LiteralPath $script:envFile)
        $lines[0] | Should -Be 'API_URL=https://api.example.com'
        (Get-Content -LiteralPath $script:envFile -Raw) | Should -Not -Match 'API_URL=http://localhost:5000API_URL='
        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:prodApiUrl
        $envValues['API_KEY'] | Should -Be $script:prodApiKey
    }

    It 'uses an explicit get instead of the dotenv template' {
        Write-ConfigMapFile $script:mapFile @'
@{
    api = @{
        _template = @{
            type = 'dotenv'
            file = 'missing.env'
        }
        get = { param($ctx, $options) 'custom-get' }
        options = @{
            local = @{ API_URL = 'x' }
        }
    }
}
'@

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop

        $result.Value | Should -Be 'custom-get'
        Test-Path (Join-Path $script:projectDir 'missing.env') | Should -BeFalse
    }

    It 'uses an explicit set instead of the dotenv template' {
        Write-ConfigMapFile $script:mapFile @'
@{
    api = @{
        _template = @{
            type = 'dotenv'
            file = '.env'
        }
        set = {
            param($ctx, $key, $value)
            'custom-set' | Set-Content 'custom-set.txt'
        }
        options = @{
            local = @{
                API_URL = 'http://localhost:5000'
                API_KEY = 'dev-key'
            }
            prod = @{
                API_URL = 'https://api.example.com'
                API_KEY = 'prod-key'
            }
        }
    }
}
'@

        qconf -map $script:mapFile api -value prod -ErrorAction Stop

        Get-Content (Join-Path $script:projectDir 'custom-set.txt') -Raw | Should -Match 'custom-set'
        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:localApiUrl
        $envValues['API_KEY'] | Should -Be $script:localApiKey
    }

    It 'gets and sets a dotenv _template entry through qbuild' {
        $buildMap = Join-Path $script:projectDir '.build.map.ps1'
        Write-ConfigMapFile $buildMap @'
[ordered]@{
    api = [ordered]@{
        _settings   = @{ process = 'options' }
        description = 'API settings'
        _template   = @{
            type = 'dotenv'
            file = '.env'
        }
        options     = @{
            local = @{
                API_URL = 'http://localhost:5000'
                API_KEY = 'dev-key'
            }
            prod = @{
                API_URL = 'https://api.example.com'
                API_KEY = 'prod-key'
            }
        }
    }
}
'@

        $result = qbuild -map $buildMap api -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'local'

        qbuild -map $buildMap api -value prod -ErrorAction Stop
        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:prodApiUrl
        $envValues['API_KEY'] | Should -Be $script:prodApiKey
    }

    It 'accepts the dotenv short-form _template string' {
        Write-ConfigMapFile $script:mapFile @'
@{
    api = @{
        _template = 'dotenv:.env'
        description = 'API settings'
        options = @{
            local = @{
                API_URL = 'http://localhost:5000'
                API_KEY = 'dev-key'
            }
            prod = @{
                API_URL = 'https://api.example.com'
                API_KEY = 'prod-key'
            }
        }
    }
}
'@

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'local'

        qconf -map $script:mapFile api -value prod -ErrorAction Stop
        $envValues = Read-DotEnvFile $script:envFile
        $envValues['API_URL'] | Should -Be $script:prodApiUrl
        $envValues['API_KEY'] | Should -Be $script:prodApiKey
    }

    It 'rejects an unknown option key' {
        { qconf -map $script:mapFile api -value nope -ErrorAction Stop } |
            Should -Throw '*option*nope*'
    }
}


Describe 'qconf user-secrets _template' {
    BeforeAll {
        function script:Read-UserSecrets {
            param([Parameter(Mandatory)][string]$Csproj)
            $result = @{}
            foreach ($line in dotnet user-secrets list --project $Csproj) {
                if ($line -match '^(.+?)\s*=\s*(.*)$') { $result[$Matches[1]] = $Matches[2] }
            }
            return $result
        }
    }

    BeforeEach {
        $script:workDir = Join-Path $TestDrive ("secrets-" + [guid]::NewGuid().ToString('n'))
        $script:projectDir = Join-Path $script:workDir 'project'
        New-Item -ItemType Directory -Path $script:projectDir -Force | Out-Null
        Push-Location $script:workDir

        $script:secretsId = [guid]::NewGuid().ToString()
        $script:csproj = Join-Path $script:projectDir 'App.csproj'
        @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <UserSecretsId>$($script:secretsId)</UserSecretsId>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath $script:csproj -Encoding utf8

        $script:mapFile = Join-Path $script:projectDir '.configuration.map.ps1'
        Write-ConfigMapFile $script:mapFile @'
@{
    api = @{
        _template = @{
            type   = 'user-secrets'
            csproj = 'App.csproj'
        }
        description = 'API secrets'
        options = @{
            local = @{
                'Api:Url' = 'http://localhost:5000'
                'Api:Key' = 'dev-key'
            }
            prod = @{
                'Api:Url' = 'https://api.example.com'
                'Api:Key' = 'prod-key'
            }
        }
    }
    short = @{
        _template = 'user-secrets:App.csproj'
        options = @{
            local = @{ 'Api:Url' = 'http://localhost:5000' }
            prod  = @{ 'Api:Url' = 'https://api.example.com' }
        }
    }
    reference = @{
        _template = 'user-secrets:.'
        options = [ordered]@{
            shared = @{ 'Db:Conn' = 'user-secrets:db_shared' }
            local  = @{ 'Db:Conn' = 'server=localhost' }
        }
    }
}
'@
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:csproj) {
            dotnet user-secrets clear --project $script:csproj 2>&1 | Out-Null
        }
        Pop-Location
    }

    It 'writes every key in the selected option as a user secret' {
        qconf -map $script:mapFile api -value prod -ErrorAction Stop

        $secrets = Read-UserSecrets $script:csproj
        $secrets['Api:Url'] | Should -Be 'https://api.example.com'
        $secrets['Api:Key'] | Should -Be 'prod-key'
    }

    It 'reads the active preset from the user secrets' {
        qconf -map $script:mapFile api -value local -ErrorAction Stop

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop

        @($result.Active) | Should -Contain 'local'
        $result.Value['Api:Url'] | Should -Be 'http://localhost:5000'
        $result.Value['Api:Key'] | Should -Be 'dev-key'
    }

    It 'reports no active preset when the secrets match none' {
        dotnet user-secrets set 'Api:Url' 'http://elsewhere' --project $script:csproj | Out-Null
        dotnet user-secrets set 'Api:Key' 'other' --project $script:csproj | Out-Null

        $result = qconf -map $script:mapFile api -porcelain -ErrorAction Stop

        $result.Active | Should -BeNullOrEmpty
        $result.Value['Api:Key'] | Should -Be 'other'
    }

    It 'accepts the short form user-secrets:{csproj}' {
        qconf -map $script:mapFile short -value prod -ErrorAction Stop

        (Read-UserSecrets $script:csproj)['Api:Url'] | Should -Be 'https://api.example.com'
        $result = qconf -map $script:mapFile short -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'prod'
    }

    It 'throws when the csproj does not exist' {
        Remove-Item -LiteralPath $script:csproj
        { qconf -map $script:mapFile api -value prod -ErrorAction Stop } |
            Should -Throw '*csproj*'
    }

    It 'throws when the short form has no csproj' {
        (Get-Content -LiteralPath $script:mapFile -Raw) -replace 'user-secrets:App.csproj', 'user-secrets:' |
            Set-Content -LiteralPath $script:mapFile -Encoding utf8

        { qconf -map $script:mapFile short -value prod -ErrorAction Stop } |
            Should -Throw '*user-secrets:*csproj*'
    }

    It 'rejects an unknown option key' {
        { qconf -map $script:mapFile api -value nope -ErrorAction Stop } |
            Should -Throw '*option*nope*'
    }

    It 'copies a user-secrets: reference from the project when csproj is a directory' {
        dotnet user-secrets set 'db_shared' 'server=shared' --project $script:csproj | Out-Null

        qconf -map $script:mapFile reference -value shared -ErrorAction Stop

        (Read-UserSecrets $script:csproj)['Db:Conn'] | Should -Be 'server=shared'
    }

    It 'throws and writes nothing when a user-secrets: reference is missing' {
        { qconf -map $script:mapFile reference -value shared -ErrorAction Stop } |
            Should -Throw '*db_shared*'

        (Read-UserSecrets $script:csproj).ContainsKey('Db:Conn') | Should -BeFalse
    }

    It 'writes no key when a later user-secrets: reference is missing' {
        Write-ConfigMapFile $script:mapFile @'
@{
    partial = @{
        _template = 'user-secrets:App.csproj'
        options = @{
            shared = [ordered]@{
                'Db:Host' = 'localhost'
                'Db:Conn' = 'user-secrets:db_shared'
            }
        }
    }
}
'@

        { qconf -map $script:mapFile partial -value shared -ErrorAction Stop } |
            Should -Throw '*db_shared*'

        (Read-UserSecrets $script:csproj).ContainsKey('Db:Host') | Should -BeFalse
    }

    It 'does not report an option as active when its user-secrets: reference is missing' {
        dotnet user-secrets set 'Db:Conn' 'server=other' --project $script:csproj | Out-Null

        $result = qconf -map $script:mapFile reference -porcelain -ErrorAction Stop

        $result.Active | Should -BeNullOrEmpty
    }

    It 'keeps unrelated secrets and non-ASCII values when setting an option' {
        dotnet user-secrets set 'Other:Key' 'keep-me' --project $script:csproj | Out-Null
        Write-ConfigMapFile $script:mapFile @'
@{
    text = @{
        _template = 'user-secrets:App.csproj'
        options = @{
            polish = @{ 'Greeting' = 'zażółć "gęślą" jaźń' }
        }
    }
}
'@

        qconf -map $script:mapFile text -value polish -ErrorAction Stop

        $secrets = Read-UserSecrets $script:csproj
        $secrets['Greeting'] | Should -Be 'zażółć "gęślą" jaźń'
        $secrets['Other:Key'] | Should -Be 'keep-me'
    }

    It 'stores an empty option value and reports it as active' {
        Write-ConfigMapFile $script:mapFile @'
@{
    clearable = @{
        _template = 'user-secrets:App.csproj'
        options = [ordered]@{
            filled = @{ 'Db:Conn' = 'server=localhost' }
            empty  = @{ 'Db:Conn' = '' }
        }
    }
}
'@

        qconf -map $script:mapFile clearable -value filled -ErrorAction Stop
        qconf -map $script:mapFile clearable -value empty -ErrorAction Stop

        $result = qconf -map $script:mapFile clearable -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'empty'
    }

    It 'matches a user-secrets: reference by its resolved value' {
        dotnet user-secrets set 'db_shared' 'server=shared' --project $script:csproj | Out-Null

        qconf -map $script:mapFile reference -value local -ErrorAction Stop

        $result = qconf -map $script:mapFile reference -porcelain -ErrorAction Stop
        @($result.Active) | Should -Contain 'local'
    }
}
