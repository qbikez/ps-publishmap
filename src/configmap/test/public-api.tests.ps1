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
            'Initialize-QBuildAgent',
            'Invoke-EntryCommand', 'Invoke-Get', 'Invoke-QBuild',
            'Invoke-QConf', 'Invoke-Set', 'Merge-IncludeDirectives',
            'Resolve-ConfigMap', 'Test-IsParentEntry'
        ) | Sort-Object

        (Get-Command -Module ConfigMap -CommandType Function).Name | Sort-Object |
            Should -Be $expectedFunctions
        (Get-Command -Module ConfigMap -CommandType Alias).Name | Sort-Object |
            Should -Be @('qbuild', 'qconf')
    }

    It 'imports a map through Import-ConfigMap' {
        $mapFile = Join-Path $TestDrive '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{ task = { "done" } }'

        $map = Import-ConfigMap -Map $mapFile

        $map.task | Should -BeOfType [hashtable]
        $map.task._baseDir | Should -Be $TestDrive
    }
}
