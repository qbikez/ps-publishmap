# PSScriptAnalyzerSettings.psd1
@{
    Severity=@(
        'Error'
        'Warning'
    )
    ExcludeRules=@(
        'PSAvoidGlobalAliases'
    #    'PSAvoidUsingWriteHost'
    )
}