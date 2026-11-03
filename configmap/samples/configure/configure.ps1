<#
.PARAMETER porcelain
    If set, the output will be a dPowerShell object that can be used in scripts (i.e.: `$result = ./configure.ps1 get -porcelain`).
    Otherwise, a nicely formatted, human-readable will be displayed.
.PARAMETER validate
    If set, will check if current configuration is valid (i.e. if all required services are running, correct azure subscription is active, etc.). Similar to `./configure.ps1 validate`
#>

[CmdletBinding()]
param(
    [ValidateSet("get", "set", "options", "list", "validate", "help")]
    $command = "get", 

    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            . "$PSScriptRoot/.configuration.map.ps1"

            $keys = @()
            foreach ($kvp in $modules.GetEnumerator()) {
                $module = $kvp.value
                if ($module.list) {
                    $moduleKeys = Invoke-Command -ScriptBlock $module.list
                    $keys += $moduleKeys | % { "$($kvp.key)/$_" }
                }
                else {
                    $keys += $kvp.key
                }
            }

            return $keys | ? { $_.startswith($wordToComplete) }
        })] 
    $module = $null,

    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            . $PSScriptRoot/.configuration.map.ps1
        
            if (!$fakeBoundParameters.ContainsKey("module")) {
                return @("__BAD__")
            }
            $moduleAndPath = $fakeBoundParameters["module"]

            $splits = $moduleAndPath.Split("/")
            $moduleName = $splits[0]
            $path = $splits[1]

            $module = $modules.$moduleName
        
            $options = Invoke-Command -ScriptBlock $module.options -ArgumentList @($path)

            return $options.Keys | ? { $_.startswith($wordToComplete) }
        })]

    $value = $null,
    [switch][bool]$validate = $false,
    [switch][bool]$porcelain = $false,
    [object]$options = $null
)

. $PSScriptRoot/.configuration.map.ps1

function write-help() {
    write-host ""
    write-host "Use ./configure.ps1 script to set advanced configuration options."
    write-host "Here are your current settings:"

    $result = ./configure.ps1
    $result | Format-Table | out-string | Write-Host -ForegroundColor Yellow
    
    write-host -NoNewline "You can change above options, using: '"
    write-host -NoNewline -ForegroundColor Blue "./configure.ps1 set {name} {value}"
    write-host "'."
    write-host ""
    write-host "For example, to set event-grid to local, run:"
    write-host "./configure.ps1 set event-grid local"
    write-host ""
    write-host "To get current configuration, run:"
    write-host "./configure.ps1 get"

}

function invoke-modulecommand($moduleAndPath, $command, [object] $additionalOpts) {
    if ($command -eq "validate") {
        $command = "get"
        $validate = $true
    }
    $splits = $moduleAndPath.Split("/")
    $moduleName = $splits[0]
    $path = $splits[1]

    $module = $modules.$moduleName
    $moduleCommand = $module.$command
    if (!$moduleCommand) {
        throw "Command $m.$command not found"
    }

    switch ($command) {
        "set" {  
            $options = Invoke-Command -ScriptBlock $module.options -ArgumentList @($path)
            if (!$options) {
                throw "module $moduleName does not support options[$path]"
            }
            if (!$value) {
                $current = invoke-modulecommand $moduleAndPath "get"
                $value = $current.Active
            }
            if (!$options.containskey($value)) {
                throw "Option $value not found for module $module"
            }
            $optionvalue = $options.$value
            
            Write-Verbose "setting $moduleAndPath = '$value' ('$optionvalue')"
            $r = Invoke-Command -ScriptBlock $moduleCommand -ArgumentList @($path, $optionvalue, $value, $additionalOpts)

            return invoke-modulecommand $moduleAndPath "validate"
        }
        { $_ -in ("get", "validate") } {
            if ($path -eq $null -and $module.list) {
                $path = Invoke-Command -ScriptBlock $module.list
            }
            if ($path -eq $null) {
                $path = ""
            }

            foreach ($subPath in @($path)) {
                Write-Verbose "getting $moduleName/$subPath"
                $options = Invoke-Command -ScriptBlock $module.options -ArgumentList @($path)
                $value = Invoke-Command -ScriptBlock $moduleCommand -ArgumentList @($subPath, $options)
                $result = $null
                
                if ($value -is [Hashtable]) {
                    $hash = @{ Path = "$moduleName/$subPath" }
                    $hash += $value
                    $result = $hash
                }
                else {
                    $result = @{ Path = "$moduleName/$subPath"; Value = $value }
                }                

                $options = invoke-modulecommand "$moduleName/$subPath" -command "options" $additionalOpts
                
                if (!$result.Active) {
                    $result.Active = $options.keys | where { $options.$_ -eq $value }
                }
                
                $result.Options = $options.keys
                
                $isvalid = "?"
                if ($validate -and $module.validate) {
                    if (!$result.Active) {
                        write-warning "no active option found for $moduleName/$subPath"
                        $isvalid = $null
                    }
                    else {
                        $optionvalue = $options.$($result.Active)
                        $isvalid = Invoke-Command $module.validate -ArgumentList @($path, $optionvalue, $result.Active)
                    }
                }

                $result = [PSCustomObject]@{
                    Path    = $result.Path
                    Value   = $result.Value
                    Active  = $result.Active
                    Options = $result.Options
                    IsValid = $isvalid
                } 
                # if ($isvalid -ne "?") {
                #     $result | Add-Member -MemberType NoteProperty -Name IsValid -Value $isvalid
                # }
                $result | Write-Output
            }
        }
        Default {
            Write-Verbose "Running $m.$command"

            Invoke-Command -ScriptBlock $moduleCommand  -ArgumentList @($path)
        }
    }

}

function get-checkmark($status) {
    if ($status -eq $true) {
        return "✅"
    }
    elseif ($status -eq $false) {
        return "❌"
    }
    else {
        return "❓"
    }
}


if ($command -eq "help") {
    write-help
    return
}

if ($module -eq $null) {
    $module = $modules.keys
}

$result = @()

foreach ($m in @($module)) {
    if (!$module) {
        throw "Module $m not found"
    }
    $status = invoke-modulecommand -moduleAndPath $m -command $command -additionalOpts $options
    foreach ($substatus in @($status)) {
        $result += $substatus
    }
}

if ($porcelain) {
    return $result
}
else {
    $result | % { 
        [PSCustomObject]@{
            Path    = $_.Path
            Active  = $_.Active
            Options = $_.Options
            IsValid = get-checkmark $_.IsValid
        }
    } | Format-Table
}