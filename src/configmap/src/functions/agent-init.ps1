$script:qbuildSkillName = 'qbuild-discover'
$script:qbuildSkillSource = Join-Path $PSScriptRoot '../../skills/qbuild-discover'

function Get-QBuildUserHome {
    if ($env:HOME) {
        return $env:HOME
    }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-QBuildAgentSkillDestination {
    <#
    .SYNOPSIS
        Resolves the install directory for the shipped qbuild agent skill.
    #>
    [OutputType([string])]
    param(
        [ValidateSet('user', 'project')]
        [string]$Scope = 'project',
        [ValidateSet('cursor', 'copilot', 'claude')]
        [string]$Agent = 'cursor',
        [string]$ProjectRoot = $null
    )

    if (!$ProjectRoot) {
        $ProjectRoot = (Get-Location).Path
    }

    $root = if ($Scope -eq 'user') { Get-QBuildUserHome } else { $ProjectRoot }
    $skillsParent = switch ($Agent) {
        'cursor' { Join-Path '.cursor' 'skills' }
        'claude' { Join-Path '.claude' 'skills' }
        'copilot' {
            if ($Scope -eq 'user') {
                Join-Path '.copilot' 'skills'
            }
            else {
                Join-Path '.github' 'skills'
            }
        }
    }

    return [System.IO.Path]::GetFullPath((Join-Path $root (Join-Path $skillsParent $script:qbuildSkillName)))
}

function New-QBuildAgentInitDynamicParam {
    <#
    .SYNOPSIS
        Builds -Scope / -Agent dynamic parameters for qbuild !agent.init.
    #>
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param()

    $dict = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

    $scopeAttributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $scopeAttributes.Add((New-Object System.Management.Automation.ParameterAttribute))
    $scopeAttributes.Add((New-Object System.Management.Automation.ValidateSetAttribute(@('user', 'project'))))
    $dict.Add('Scope', (New-Object System.Management.Automation.RuntimeDefinedParameter('Scope', [string], $scopeAttributes)))

    $agentAttributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    $agentAttributes.Add((New-Object System.Management.Automation.ParameterAttribute))
    $agentAttributes.Add((New-Object System.Management.Automation.ValidateSetAttribute(@('cursor', 'copilot', 'claude'))))
    $dict.Add('Agent', (New-Object System.Management.Automation.RuntimeDefinedParameter('Agent', [string], $agentAttributes)))

    return $dict
}

function Initialize-QBuildAgent {
    <#
    .SYNOPSIS
        Installs the shipped qbuild-discover skill for a coding agent.
    .PARAMETER Scope
        project (default) installs under the current directory; user installs under $HOME.
    .PARAMETER Agent
        Target agent harness: cursor (default), copilot, or claude.
    #>
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('user', 'project')]
        [string]$Scope = 'project',
        [ValidateSet('cursor', 'copilot', 'claude')]
        [string]$Agent = 'cursor',
        [string]$ProjectRoot = $null
    )

    $source = [System.IO.Path]::GetFullPath($script:qbuildSkillSource)
    $sourceSkill = Join-Path $source 'SKILL.md'
    if (!(Test-Path -LiteralPath $sourceSkill)) {
        throw "Shipped skill not found at '$sourceSkill'."
    }

    $destination = Get-QBuildAgentSkillDestination -Scope $Scope -Agent $Agent -ProjectRoot $ProjectRoot
    $destinationParent = Split-Path $destination -Parent
    if (!(Test-Path -LiteralPath $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    Copy-Item -Path $source -Destination $destination -Recurse -Force

    $installedSkill = Join-Path $destination 'SKILL.md'
    Write-Host "Installed qbuild agent skill for $Agent ($Scope scope) at '$installedSkill'"

    return [pscustomobject]@{
        Scope       = $Scope
        Agent       = $Agent
        Source      = $source
        Destination = $destination
        SkillPath   = $installedSkill
    }
}
