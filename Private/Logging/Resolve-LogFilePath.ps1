function Resolve-LogFilePath {
    <#
    .SYNOPSIS
        Resolves the full log file path from the Logging.File configuration.
    .DESCRIPTION
        Expands environment variables in the configured Path (e.g. %USERPROFILE%) and any
        {DateFormatToken} placeholders in the configured FileName (e.g. {yyyyMMdd}) using
        .NET date format strings evaluated against the current date, then ensures the target
        directory exists.
    .PARAMETER File
        The Logging.File section (Path, FileName) as returned by Get-LoggingConfig.
    .OUTPUTS
        String. Full path to the log file to append to.
    .EXAMPLE
        Resolve-LogFilePath -File $loggingConfig.File
        Returns e.g. 'C:\Users\alice\Documents\Logs\IAMENGINE-20260812.log'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $File
    )

    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($File.Path)

    $expandedFileName = [regex]::Replace($File.FileName, '\{([^}]+)\}', {
        param($match)
        (Get-Date).ToString($match.Groups[1].Value)
    })

    if (-not (Test-Path -Path $expandedPath)) {
        New-Item -ItemType Directory -Path $expandedPath -Force | Out-Null
    }

    Join-Path -Path $expandedPath -ChildPath $expandedFileName
}
