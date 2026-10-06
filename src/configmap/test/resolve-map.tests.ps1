BeforeAll {
    Get-Module ConfigMap -ErrorAction SilentlyContinue | Remove-Module
    Import-Module $PSScriptRoot\..\configmap.psm1
}

Describe 'Resolve-ConfigMapFile' {
    It 'uses only explicit parameters to resolve a fallback path' {
        $mapFile = Join-Path $TestDrive '.build.map.ps1'
        Set-Content -Path $mapFile -Value '@{}'

        & (Get-Module ConfigMap) {
            param($Fallback)

            Resolve-ConfigMapFile -MapFile $null -Fallback $Fallback -LookUp:$false
        } $mapFile | Should -Be $mapFile
    }

    It 'does not search parent directories when lookup is disabled' {
        $parentMapFile = Join-Path $TestDrive '.build.map.ps1'
        $childDirectory = Join-Path $TestDrive 'child'
        New-Item -ItemType Directory -Path $childDirectory -Force | Out-Null
        Set-Content -Path $parentMapFile -Value '@{}'

        Push-Location $childDirectory
        try {
            {
                & (Get-Module ConfigMap) {
                    Resolve-ConfigMapFile -MapFile '.build.map.ps1' -LookUp:$false
                }
            } | Should -Throw "*not found"
        }
        finally {
            Pop-Location
        }
    }
}

Describe 'Import-IncludedConfigMap' {
    It 'caches imported maps and sets their base directory' {
        $includeDirectory = Join-Path $TestDrive 'child'
        New-Item -ItemType Directory -Path $includeDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $includeDirectory '.build.map.ps1') -Value '@{ task = { "done" } }'
        $cache = @{}
        $loading = @{}

        & (Get-Module ConfigMap) {
            param($BaseDir, $ExpectedBaseDir, $Cache, $Loading)

            $first = Import-IncludedConfigMap -DirectoryName 'child' -BaseDir $BaseDir -Cache $Cache -Loading $Loading
            $second = Import-IncludedConfigMap -DirectoryName 'child' -BaseDir $BaseDir -Cache $Cache -Loading $Loading

            $first | Should -Be $second
            $first._baseDir | Should -Be $ExpectedBaseDir
            $first.task._baseDir | Should -Be $ExpectedBaseDir
        } $TestDrive $includeDirectory $cache $loading
    }

    It 'returns null when an include directory has no map' {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'empty') -Force | Out-Null

        & (Get-Module ConfigMap) {
            param($BaseDir)

            Import-IncludedConfigMap -DirectoryName 'empty' -BaseDir $BaseDir -Cache @{} -Loading @{} |
                Should -BeNullOrEmpty
        } $TestDrive
    }
}
