$targets = @{
    "test" = {
       invoke-pester .
    }
}

return $targets
