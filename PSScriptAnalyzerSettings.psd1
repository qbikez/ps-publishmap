# PSScriptAnalyzerSettings.psd1
@{
    Severity=@(
        'Error'
        'Warning'
    )
    Rules = @{
        'PSAvoidUsingCmdletAliases' = @{
            'Whitelist' = @('cd','%','select','where','pushd','popd','gi','Increment-Version')
        }
        'PSUseConsistentIndentation' = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        'PSUseConsistentWhitespace' = @{
            Enable          = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckSeparator  = $true
        }
        'PSAlignAssignmentStatement' = @{
            Enable         = $true
            CheckHashtable = $true
        }
    }
    ExcludeRules=@(
        'PSAvoidUsingWriteHost'
    )
}