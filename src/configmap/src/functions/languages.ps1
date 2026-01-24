#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list", "#include")
    }
    "conf"  = @{
        reservedKeys = @("exec", "list", "#include", "options", "get", "set", "validate")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}
