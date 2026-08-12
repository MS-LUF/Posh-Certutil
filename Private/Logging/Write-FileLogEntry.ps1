function Write-FileLogEntry {
    <#
    .SYNOPSIS
        Appends one formatted log line to the configured log file.
    .DESCRIPTION
        Resolves the log file path from the Logging.File configuration and appends a single
        line. Never throws: a failure (bad path, permissions, locked file) is surfaced once
        per session via Write-Warning and silently skipped afterwards, so a broken logging
        destination never interrupts the calling cmdlet's actual certutil/certreq work.
    .PARAMETER File
        The Logging.File section (Path, FileName) as returned by Get-LoggingConfig.
    .PARAMETER Entry
        The log entry object (Timestamp, Level, UserName, CmdletName, ProfileName, CAServer,
        Message) as built by Write-PWSHCertutilLog.
    .EXAMPLE
        Write-FileLogEntry -File $loggingConfig.File -Entry $entry
        Appends $entry to the resolved log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $File,

        [Parameter(Mandatory)]
        [PSCustomObject] $Entry
    )

    try {
        $logPath = Resolve-LogFilePath -File $File

        $context = $Entry.CmdletName
        if ($Entry.ProfileName) { $context += " Profile=$($Entry.ProfileName)" }
        if ($Entry.CAServer)    { $context += " CAServer=$($Entry.CAServer)" }

        $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] [{2}] [{3}] {4}' -f `
            $Entry.Timestamp, $Entry.Level.ToUpper(), $Entry.UserName, $context, $Entry.Message

        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch {
        if (-not $script:LoggingSinkFailed) {
            $script:LoggingSinkFailed = $true
            Write-Warning "Posh-Certutil file logging failed and will be skipped for the rest of this session: $_"
        }
    }
}
