@{
    "top-level" = {
        Write-Host "top level task"
    }
    "#include"  = @{
        "child" = @{
            prefix = $false
        }
    }
}