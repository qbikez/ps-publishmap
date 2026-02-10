@{
    "inner-task-1" = {
        Write-Host "Executing child task 1 from $PSScriptRoot inside $($PWD.Path)"
        return @{
            psscriptroot = $PSScriptRoot
            pwd          = $PWD.Path
        }
    }
    "inner-2"      = {
        Write-Host "Executing child task 2 from $PSScriptRoot inside $($PWD.Path)"
        return @{
            psscriptroot = $PSScriptRoot
            pwd          = $PWD.Path
        }
    }
}