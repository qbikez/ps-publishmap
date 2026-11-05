BeforeAll {
    . $PSScriptRoot/includes.ps1 -internal

    function New-TemporaryFile () {
        $f = New-Item -ItemType File "TestDrive:/$([Guid]::NewGuid().ToString())"
        return $f
    }
}

Describe "object cache" {
    Context "When getting object from cache for non-existing file" {
        It "Should throw" {
            { get-cachedobject "non-existing-file" } | Should -Throw
        }
    }
    Context "When getting fresh object from cache for existing file" {
        BeforeAll {
            $f = New-TemporaryFile
        }
        It "Should return null" {
            { get-cachedobject $f.fullname } | Should -Not -Throw
            get-cachedobject $f.fullname | Should -BeNullOrEmpty
        }
    }

    Context "When setting cached object" {
        BeforeAll {
            $f = New-TemporaryFile
            $obj = new-object -type pscustomobject -Property @{ name = "test1" }
        }
        It "Should set" {
            {
                set-cachedobject $f.fullname $obj
            } | Should -Not -Throw
        }
        It "Should return same object" {
            $cached = get-cachedobject $f.fullname
            $cached | Should -Not -BeNullOrEmpty
            $cached.value | Should -Be $obj
        }
    }

    Context "When triggerfile is modified" {
        BeforeAll {
            $f = New-TemporaryFile
            $obj = new-object -type pscustomobject -Property @{ name = "test1" }
        }
        It "Should set" {
            {
                set-cachedobject $f.fullname $obj
            } | Should -Not -Throw
        }
        It "Should return null" {
            $f.LastWriteTimeUtc = $f.LastWriteTimeUtc.AddSeconds(1)
            $cached = get-cachedobject $f.fullname
            $cached | Should -BeNullOrEmpty
        }
    }
}
