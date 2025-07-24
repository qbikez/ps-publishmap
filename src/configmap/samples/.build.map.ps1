@{
    "write:simple"  = {
        param([string] $message)
        
        write-host "WRITE: '$message'"
    }
    "write:wrapped" = @{
        exec  = {
            param([string] $message)
        
            write-host "WRAPPED: '$message'"
        }

        other = {
            param([string] $message)
        
            write-host "OTHER: '$message'"
        }
    }
    "write:custom"  = @{
        go = {
            param([string] $message)
            return "CUSTOM: '$message'"
        }
    }
    "write:getset"  = @{
        go = {
            param([string] $message)
            return "GO: '$message'"
        }
        get = { 
            param([string] $message)
            return "GET: '$message'"
        }
        set = {
            param([string] $message)
            write-host "SET: '$message'"
        }
    }
    
    "write:options" = {
        options = {
            return @{
                "option1" = "value1"
                "option2" = "value2"
            }
        }
        get = { 
            param([string] $message)
            return "GET: '$message'"
        }
        set = {
            param([string] $value, [string] $key)
            write-host "SET: '$key' to '$value'"
        }
    }
    
}