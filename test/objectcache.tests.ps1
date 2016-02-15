. $psscriptroot\includes.ps1 -internal

Describe "object cache" {
    function New-TemporaryFile () {
        $f = New-item -type file "testdrive:\$([Guid]::NewGuid().ToString())"
        return $f
    }
    Context "When getting object from cache for non-existing file" {
        It "Should throw" {
             { get-cachedobject "non-existing-file" } | should Throw
        }
    }
    Context "When getting fresh object from cache for existing file" {
        $f = New-TemporaryFile
        It "Should return null" {
            { get-cachedobject $f.fullname } | should not Throw
            get-cachedobject $f.fullname | should BeNullOrEmpty
        }
    }
    
    Context "When setting cached object" {
       $f = New-TemporaryFile
       $obj = new-object -type pscustomobject -Property @{ name = "test1" }
       It "Should set" {
            { 
                set-cachedobject $f.fullname $obj 
            } | Should Not Throw
       }
       It "Should return same object" {
             $cached = get-cachedobject $f.fullname 
             $cached | Should Not BeNullOrEmpty
             $cached.value | Should Be $obj
       }
    }
    
    Context "When triggerfile is modified" {
       $f = New-TemporaryFile
       $obj = new-object -type pscustomobject -Property @{ name = "test1" }
       It "Should set" {
            { 
                set-cachedobject $f.fullname $obj 
            } | Should Not Throw
       }
       touch $f
       It "Should return null" {
             $cached = get-cachedobject $f.fullname 
             $cached | Should BeNullOrEmpty
       }
    }
}