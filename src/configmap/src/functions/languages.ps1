#requires -version 7.0

$script:languages = @{
    "build" = @{
        reservedKeys = @("exec", "list")
    }
    "conf"  = @{
        reservedKeys = @("options", "exec", "list", "get", "set", "validate")
    }
}

function Get-MapLanguage {
    param([ValidateSet("build", "conf")]$language)
    return $script:languages.$language
}
