function Get-ConfigMapExecProcessDynamicParam {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $result = Get-EntryDynamicParam $Context.Map $Context.Entry $Context.Command -skip 0 -bound $Context.BoundParameters
    Write-Debug "Dynamic parameters for entry '$($Context.Entry)': $($result.Keys -join ', ')"
    return $result
}

function Invoke-ConfigMapExecProcess {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $map = $Context.Map
    $userMap = $Context.UserMap
    $mapPath = $Context.MapArgument
    $entry = $Context.Entry
    $command = $Context.Command
    $invocation = $Context.Invocation
    $operationContext = $Context.OperationContext
    $isInternalCommand = Test-ConfigMapInternalCommand -Name $entry -Language build

    $targets = Get-MapEntries $map $entry -language "build" -OperationContext $operationContext

    if (!$targets -or $targets.Count -eq 0) {
        throw "Entry '$entry' not found. Run 'qbuild list' to see all available commands."
    }

    Write-Verbose "running targets: $($targets.Key)"

    $bound = @{}
    foreach ($item in $Context.BoundParameters.GetEnumerator()) {
        if ($item.Key -notin @('entry', 'ProcessAction', 'ProcessValue', 'RemainingArguments')) {
            $bound[$item.Key] = $item.Value
        }
    }
    $passthrough = Get-ConfigMapProcessPassthrough `
        -ProcessAction $Context.ProcessAction `
        -ProcessValue $Context.ProcessValue `
        -RemainingArguments $Context.RemainingArguments
    if ($isInternalCommand) {
        $bound._context = @{
            Map                = $map
            UserMap            = $userMap
            MapArgument        = $mapPath
            Invocation         = $invocation
            RemainingArguments = @($passthrough)
        }
    }
    elseif ($passthrough.Count -gt 0) {
        $bound._context = @{}
        $bound._context['additionalArgs'] = @($passthrough)
    }

    $hookContext = @{
        MainCommand        = 'qbuild'
        Entry              = $entry
        Targets            = @($targets)
        Map                = $map
        MapPath            = $mapPath
        Command            = $command
        Bound              = $bound
        RemainingArguments = $passthrough
    }

    $hookEntryKey = if ($entry -match '^(.*)\.all$') { $Matches[1] } else { [string]$entry }
    $hookEntry = $map
    if ($hookEntryKey) {
        $resolvedHookEntry = Get-MapEntry $map $hookEntryKey -language "build" -OperationContext $operationContext
        if ($null -ne $resolvedHookEntry) {
            $hookEntry = $resolvedHookEntry
        }
    }

    $hookResult = Invoke-WithEntrySettings -Map $map -EntryKey $hookEntryKey -Entry $hookEntry -OperationContext $operationContext -ScriptBlock {
        Invoke-ConfigMapPluginHooks -HookName 'InvokeQBuildTargets' -Context $hookContext
    }
    if ($hookResult.Handled) {
        return $hookResult.Result
    }

    foreach ($target in $targets) {
        $targetKey = $target.key
        $targetEntry = $target.value
        Write-Verbose "running entry '$targetKey'"

        if ($command -eq "exec" `
                -and $targetEntry -is [System.Collections.IDictionary] `
                -and -not (Get-EntryHasExec $targetEntry) `
                -and (Test-IsParentEntry $targetEntry)) {
            Write-ChooseSubcommand -parentKey $targetKey -parentEntry $targetEntry -invocation $invocation -language "build"
            return
        }

        Invoke-WithEntrySettings -Map $map -EntryKey $targetKey -Entry $targetEntry -OperationContext $operationContext -ScriptBlock {
            Invoke-EntryWrapper -MainCommand 'qbuild' -TargetKey $targetKey -TargetEntry $targetEntry -Command $command -Bound $bound -RemainingArguments $passthrough
        }
    }
}

function Register-ConfigMapExecProcess {
    Register-ConfigMapProcess -Name $script:ConfigMapDefaultProcessName -Invoke {
        param($Context)
        Invoke-ConfigMapExecProcess -Context $Context
    } -GetDynamicParam {
        param($Context)
        Get-ConfigMapExecProcessDynamicParam -Context $Context
    }
}

Register-ConfigMapExecProcess
