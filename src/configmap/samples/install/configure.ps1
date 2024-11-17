
[CmdletBinding()]
param(
    [ArgumentCompleter({
            param ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $modules = . "$PSScriptRoot/.configuration.map.ps1"

            $list = convertto-completionList $modules
            $keys = $list.keys
            return $keys | ? { $_.startswith($wordToComplete) }
        })] 
    $module = $null
)


$modules = . $PSScriptRoot/.configuration.map.ps1
$list = convertto-completionList $modules

$scripts = @{
    essentials = {
        & "$psscriptroot/bootstrap.ps1"
        #winget
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

        #pwsh
        # winget install --id Microsoft.Powershell.Preview --source winget # done by install.yaml

        # chocolatey
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        # choco install -y oh-my-posh
        # oh-my-posh font install FiraCode

        choco install -y gsudo
        gsudo config PowerShellLoadProfile true
        choco install powershell-core

        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

        install-module require
        import-module require

        # todo: if you run this as admin, you also need to do it for each specific user?
        req pathutils -scope AllUsers
        req cd-extras -scope AllUsers
        req posh-git -scope AllUsers
    }
}

write-verbose "installing targets: $target" -verbose
@($module) | % {
    if ($_ -is [ScriptBlock]) {
        & $_
        return
    }
    
    $target = $list[$module]
    if (!$target) {
        Write-Warning "No module '$module' found."
        continue
    }

    if ($null -eq $target.list) {
        write-verbose "installing '$($target.name)'" -verbose
        install-mypackage $target
    }
    else {
        write-verbose "installing group '$module'" -verbose
        install-mygroup $target
    }
}