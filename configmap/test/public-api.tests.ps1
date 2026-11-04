BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe 'ConfigMap public API' {
    It 'exports only the documented commands and advanced functions' {
        $expectedFunctions = @(
            'Add-BaseDir', 'Assert-ConfigMap', 'ConvertTo-MapResult',
            'Get-CompletionList', 'Get-ConfigMapCommandCatalog',
            'Get-EntryCommand', 'Get-EntryCompletion',
            'Get-EntryDynamicParam', 'Get-MapEntries', 'Get-MapEntry',
            'Get-MapLanguage', 'Get-ScriptArgs',
            'Import-ConfigMap', 'Initialize-BuildMap', 'Initialize-ConfigMap',
            'Initialize-ProcessMap', 'Initialize-QBuildAgent',
            'Invoke-EntryCommand', 'Invoke-Get', 'Invoke-QBuild',
            'Invoke-QConf', 'Invoke-QRun', 'Invoke-Set', 'Merge-IncludeDirectives',
            'Resolve-ConfigMap', 'Test-IsParentEntry'
        ) | Sort-Object

        (Get-Command -Module ConfigMap -CommandType Function).Name | Sort-Object |
            Should -Be $expectedFunctions
        (Get-Command -Module ConfigMap -CommandType Alias).Name | Sort-Object |
            Should -Be @('qbuild', 'qconf', 'qrun')
    }

    # Map files are dot-sourced inside the module, so their scriptblocks see module-scope helpers.
    # samples/dotenv and skills/qbuild-templates document these; samples/configure calls Get-AppsettingsObject.
    It 'resolves the documented config helpers from map scriptblocks' {
        $mapFile = Join-Path $TestDrive '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ helpers = { "get-appsettings", "set-appsettings", "Find-ActiveOption", "Get-AppsettingsObject", "get-envsetting", "set-envsetting", "get-envsettingsObject", "set-envsettingsObject" | Where-Object { Get-Command $_ -ErrorAction Ignore } } }'

        $map = Import-ConfigMap -Map $mapFile

        & $map.helpers.exec | Should -Be @(
            'get-appsettings', 'set-appsettings', 'Find-ActiveOption', 'Get-AppsettingsObject',
            'get-envsetting', 'set-envsetting', 'get-envsettingsObject', 'set-envsettingsObject'
        )
    }

    It 'does not load unrelated legacy helpers into module scope' {
        $legacy = 'Create-JWT', 'execute-sql', 'Get-SSOToken', 'make-alias', 'inherit-base',
            'replace-values', 'test-httpUrl', 'get-xmlconfiguration', 'set-xmlconfiguration',
            'compare-optionsWithValues', 'get-dockerContainerVersion', 'start-dockerContainer'

        & (Get-Module ConfigMap) { param($names) $names | Where-Object { Get-Command $_ -ErrorAction Ignore } } $legacy |
            Should -BeNullOrEmpty
    }

    It 'imports a map through Import-ConfigMap' {
        $mapFile = Join-Path $TestDrive '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ task = { "done" } }'

        $map = Import-ConfigMap -Map $mapFile

        $map.task | Should -BeOfType [hashtable]
        $map.task._baseDir | Should -Be $TestDrive
    }
}
