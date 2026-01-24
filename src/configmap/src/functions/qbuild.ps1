function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    # ipmo configmap
                    $map = $fakeBoundParameters.map
                    $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1"
                    if (!(Test-Path $map)) {
                        return @("!init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = Resolve-ConfigMap $map | % { 
                        if ($_ -is [string]) {
                            $loadedMap = . $_
                            $baseDir = Split-Path $_ -Parent
                            Add-BaseDir $loadedMap $baseDir
                        } else {
                            $_
                        }
                    } | Assert-ConfigMap
                    return Get-EntryCompletion $map -language "build" @PSBoundParameters
                }
                catch {
                    return "ERROR [-entry]: $($_.Exception.Message) $($_.ScriptStackTrace)"
                }
            })]
        $entry = $null,
        $command = "exec",
        $map = "./.build.map.ps1"
    )
    dynamicparam {
        try {
            $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" | % { 
            if ($_ -is [string]) {
                $loadedMap = . $_
                $baseDir = Split-Path $_ -Parent
                Add-BaseDir $loadedMap $baseDir
            } else {
                $_
            }
        } | Assert-ConfigMap
            $result = Get-EntryDynamicParam $map $entry $command -skip 0 -bound $PSBoundParameters
            Write-Debug "Dynamic parameters for entry '$entry': $($result.Keys -join ', ')"
            return $result
        }
        catch {
            return "ERROR [dynamic]: $($_.Exception.Message) $($_.ScriptStackTrace)"
        }
    }

    process {
        if ($entry -eq "help") {
            Write-Host "QBUILD"
            Write-Host "A command line tool to manage build scripts"
            Write-Host ""
            Write-Host "Usage:"
            Write-Host "qbuild <your-script-name>"
            return
        }
        if ($entry -eq "list") {
            $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" | % { 
                if ($_ -is [string]) {
                    $loadedMap = . $_
                    $baseDir = Split-Path $_ -Parent
                    Add-BaseDir $loadedMap $baseDir
                } else {
                    $_
                }
            }
            if (!$map) {
                $invocation = $MyInvocation
                Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
                return
            }
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }
        if ($entry -eq "!init") {
            $resolvedMap = Resolve-ConfigMap $map -ErrorAction Ignore -lookUp:$false
            if (!$resolvedMap) {
                Initialize-BuildMap -file $map
                return
            }

            $loadedMap = $resolvedMap | % { . $_ }
            if (!$loadedMap) {
                if ($map -isnot [string]) {
                    throw "Map appears to be an object, not a file"
                }
                if ((Test-Path $map)) {
                    throw "map file '$map' already exists"
                }

                Initialize-BuildMap -file $map

                return
            }
            else {
                $completionList = Get-CompletionList $loadedMap -language "build"
                if ($completionList.Keys -notcontains "!init") {
                    throw "map file '$map' already exists"
                }
                else {
                    # continue with executing "init" command
                }
            }

        }

        $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" -ErrorAction Ignore | % { 
            if ($_ -is [string]) {
                $loadedMap = . $_
                $baseDir = Split-Path $_ -Parent
                Add-BaseDir $loadedMap $baseDir
            } else {
                $_
            }
        }
        if (!$map) {
            $invocation = $MyInvocation
            $commandName = $invocation.Statement

            Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
            return
        }

        # If no entry is provided, list all available scripts
        if (-not $entry) {
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }

        $targets = Get-MapEntries $map $entry
        Write-Verbose "running targets: $($targets.Key)"

        @($targets) | % {
            Write-Verbose "running entry '$($_.key)'"
            # FIXME: we already have the entry in $_.value, we know ITs own key, but we don't want to search for this key inside this object
            # we should pass null instead?
            #Invoke-EntryCommand -entry $_.value -key $_.Key $bound
            $bound = $PSBoundParameters
            $bound.Remove("entry") | Out-Null
            Invoke-EntryCommand -entry $_.value -key $command -bound $bound
        }

    }
}

Set-Alias -Name "qbuild" -Value "Invoke-QBuild" -Force
