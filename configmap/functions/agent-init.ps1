function Get-QBuildUserHome {
    if ($env:HOME) {
        return $env:HOME
    }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-QBuildShippedSkillsRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../skills'))
}

function Get-QBuildShippedSkills {
    <#
    .SYNOPSIS
        Lists shipped agent skill directories that contain SKILL.md.
    #>
    [OutputType([pscustomobject])]
    param()

    $root = Get-QBuildShippedSkillsRoot
    if (!(Test-Path -LiteralPath $root)) {
        return @()
    }

    Get-ChildItem -LiteralPath $root -Directory |
        ForEach-Object {
            $skillPath = Join-Path $_.FullName 'SKILL.md'
            if (Test-Path -LiteralPath $skillPath) {
                [pscustomobject]@{
                    Name      = $_.Name
                    Directory = $_.FullName
                    SkillPath = $skillPath
                }
            }
        } |
        Sort-Object Name
}

function Get-QBuildAgentSkillsParent {
    <#
    .SYNOPSIS
        Resolves the agent skills parent directory (does not include a skill name).
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

    return [System.IO.Path]::GetFullPath((Join-Path $root $skillsParent))
}

function Get-QBuildAgentSkillDestination {
    <#
    .SYNOPSIS
        Resolves the install directory for a shipped agent skill.
    #>
    [OutputType([string])]
    param(
        [ValidateSet('user', 'project')]
        [string]$Scope = 'project',
        [ValidateSet('cursor', 'copilot', 'claude')]
        [string]$Agent = 'cursor',
        [string]$ProjectRoot = $null,
        [Parameter(Mandatory = $true)]
        [string]$SkillName
    )

    $parent = Get-QBuildAgentSkillsParent -Scope $Scope -Agent $Agent -ProjectRoot $ProjectRoot
    return [System.IO.Path]::GetFullPath((Join-Path $parent $SkillName))
}

function Show-QBuildAgentSkills {
    <#
    .SYNOPSIS
        Prints shipped agent skill markdown to the success stream (stdout).
    #>
    [OutputType([string])]
    param(
        [string]$Name
    )

    $skills = @(Get-QBuildShippedSkills)
    if ($skills.Count -eq 0) {
        throw "No shipped agent skills found under '$(Get-QBuildShippedSkillsRoot)'."
    }

    if ($Name) {
        $match = $skills | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $match) {
            $available = ($skills | ForEach-Object { $_.Name }) -join ', '
            throw "Unknown agent skill '$Name'. Available: $available"
        }
        return Get-Content -LiteralPath $match.SkillPath -Raw
    }

    $parts = foreach ($skill in $skills) {
        $header = "# skill: $($skill.Name)"
        $body = Get-Content -LiteralPath $skill.SkillPath -Raw
        "$header`n`n$body".TrimEnd() + "`n"
    }
    return ($parts -join "`n")
}

function Initialize-QBuildAgent {
    <#
    .SYNOPSIS
        Installs all shipped ConfigMap agent skills for a coding agent.
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

    $skills = @(Get-QBuildShippedSkills)
    if ($skills.Count -eq 0) {
        throw "No shipped agent skills found under '$(Get-QBuildShippedSkillsRoot)'."
    }

    $skillsParent = Get-QBuildAgentSkillsParent -Scope $Scope -Agent $Agent -ProjectRoot $ProjectRoot
    if (!(Test-Path -LiteralPath $skillsParent)) {
        New-Item -ItemType Directory -Path $skillsParent -Force | Out-Null
    }

    $installed = foreach ($skill in $skills) {
        $destination = Join-Path $skillsParent $skill.Name
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        Copy-Item -Path $skill.Directory -Destination $destination -Recurse -Force
        $installedSkill = Join-Path $destination 'SKILL.md'
        [pscustomobject]@{
            Name        = $skill.Name
            Source      = $skill.Directory
            Destination = $destination
            SkillPath   = $installedSkill
        }
    }

    $installedList = @($installed)
    Write-Host "Installed $($installedList.Count) ConfigMap agent skill(s) for $Agent ($Scope scope) under '$skillsParent'"

    return [pscustomobject]@{
        Scope        = $Scope
        Agent        = $Agent
        SkillsParent = $skillsParent
        Skills       = $installedList
        Destination  = $skillsParent
        SkillPath    = $installedList[0].SkillPath
    }
}
