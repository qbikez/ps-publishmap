function Invoke-QBuild {
    [CmdletBinding()]
    param(
        [ArgumentCompleter({
                param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                try {
                    $mapPath = if ($fakeBoundParameters.map) { $fakeBoundParameters.map } else { "./.build.map.ps1" }
                    $localMapExists = Test-Path $mapPath

                    $resolved = Resolve-ConfigMap $fakeBoundParameters.map -fallback "./.build.map.ps1" -ErrorAction Ignore
                    if (!$resolved -or ($resolved.source -eq "file" -and !(Test-Path $resolved.sourceFile))) {
                        return @("!init", "help", "list") | ? { $_.startswith($wordToComplete) }
                    }
                    $map = $resolved | % {
                        if ($_.source -eq "file") {
                            $_.map = . $_.sourceFile | Add-BaseDir -baseDir $_.sourceFile
                        }
                        $_
                    } | % { $_.map } | Assert-ConfigMap

                    $completions = Get-EntryCompletion $map -language "build" @PSBoundParameters
                    # Include !init if no local map file exists
                    if (!$localMapExists) {
                        $completions = @("!init" | ? { $_.startswith($wordToComplete) }) + $completions
                    }
                    return $completions
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
                if ($_.source -eq "file") {
                    $_.map = . $_.sourceFile | Add-BaseDir -baseDir $_.sourceFile
                }
                $_
            } | % { $_.map } | Assert-ConfigMap
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
                if ($_.source -eq "file") {
                    $_.map = . $_.sourceFile | Add-BaseDir -baseDir $_.sourceFile
                }
                $_
            } | % { $_.map }
            if (!$map) {
                $invocation = $MyInvocation
                Write-Help -invocation $invocation -mapPath "./.build.map.ps1"
                return
            }
            Write-MapHelp -map $map -invocation $MyInvocation
            return
        }
        if ($entry -eq "!init") {
            # Only check current directory - create new map regardless of parent configs
            if (Test-Path $map) {
                throw "map file '$map' already exists"
            }
            Initialize-BuildMap -file $map
            return
        }

        $map = Resolve-ConfigMap $map -fallback "./.build.map.ps1" -ErrorAction Ignore | % {
            if ($_.source -eq "file") {
                $_.map = . $_.sourceFile | Add-BaseDir -baseDir $_.sourceFile
            }
            $_
        } | % { $_.map }
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
