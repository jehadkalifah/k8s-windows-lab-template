$ErrorActionPreference = "Stop"

function Get-VBoxManagePath {
    $command = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidates = @(
        "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe",
        "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe"
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw @"
VirtualBox appears to be missing, or VBoxManage.exe could not be found.

Checked:
  - Windows PATH
  - $env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe
  - ${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe

Install VirtualBox or update this helper if VirtualBox is installed in a custom path.
"@
}
