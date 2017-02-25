function get-envinfo($checkcommands) {
    write-warning "Powershell version:"
    $PSVersionTable.PSVersion
    
    write-warning "Available commands:"
    if ($checkcommands -eq $null) {
        $commands = "Install-Module"
    } else {
        $commands = $checkcommands
    }
        
    $commands | ForEach {
        $c = $_
        try {
            $cmd = get-command $c -ErrorAction SilentlyContinue
        } catch {
            $cmd = $null
        }
        if ($cmd -eq $null) {
            write-warning "$($c):`t MISSING"            
        }
        else {
             write-host "$($c):`t $(($cmd | format-table -HideTableHeaders | out-string) -replace ""`r`n"",'')"
        }
    }
    
}
