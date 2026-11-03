[ordered]@{
    "setup" = [ordered]@{
        description  = "Example multi-step process with durable state"

        "create-dir" = {
            New-Item -ItemType Directory -Path "out" -Force | Out-Null
            Write-Host "created out/"
        }

        "write-file" = {
            "hello from qrun" | Set-Content -Path "out/hello.txt"
            Write-Host "wrote out/hello.txt"
        }

        "verify"     = {
            if (!(Test-Path "out/hello.txt")) {
                throw "out/hello.txt is missing"
            }
            Write-Host "verified out/hello.txt"
        }
    }
}
