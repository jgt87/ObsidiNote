# ObsidiNote installer bootstrap (the same install command as CCBridge/StreamHub):
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jgt87/ObsidiNote/main/install.ps1 | iex"
# This file is ONE line of code on purpose: some shells hand a piped script to iex line by line,
# which breaks every multi-line block. That line downloads the real installer
# (tools/install-main.ps1) as a file and runs it with -File, so it works either way.
# Keep it that way: no blank lines, no second line of code (tests/InstallBootstrap.Tests.ps1).
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; $obsnInstaller = Join-Path $env:TEMP 'obsidinote-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/jgt87/ObsidiNote/main/tools/install-main.ps1' -OutFile $obsnInstaller -UseBasicParsing; & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $obsnInstaller