function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes one entry to the configured Windows Event Log, creating the source if needed.
    .DESCRIPTION
        Ensures the configured event source exists (registering it under the configured log
        name via New-EventLog if not — this requires an elevated session the first time),
        then writes the entry with the EventId/EntryType matching its level. Debug-level
        entries are written as Information entries (there is no dedicated Debug event ID or
        entry type in Windows Event Log) with the message prefixed [DEBUG].

        Never throws: a failure (source creation denied, log unreachable) is surfaced once
        per session via Write-Warning and that entry is skipped, so a broken logging
        destination never interrupts the calling cmdlet's actual certutil/certreq work.
    .PARAMETER EventLog
        The Logging.EventLog section as returned by Get-LoggingConfig.
    .PARAMETER Entry
        The log entry object (Timestamp, Level, UserName, CmdletName, ProfileName, CAServer,
        Message) as built by Write-PWSHCertutilLog.
    .EXAMPLE
        Write-EventLogEntry -EventLog $loggingConfig.EventLog -Entry $entry
        Writes $entry to the configured Windows Event Log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $EventLog,

        [Parameter(Mandatory)]
        [PSCustomObject] $Entry
    )

    try {
        if (-not (Test-EventSourceExists -Source $EventLog.Source)) {
            New-EventLog -LogName $EventLog.LogName -Source $EventLog.Source
        }

        $entryType = [System.Diagnostics.EventLogEntryType]::Information
        $eventId   = $EventLog.EventIdInformation
        if ($Entry.Level -eq 'Warning') {
            $entryType = [System.Diagnostics.EventLogEntryType]::Warning
            $eventId   = $EventLog.EventIdWarning
        } elseif ($Entry.Level -eq 'Error') {
            $entryType = [System.Diagnostics.EventLogEntryType]::Error
            $eventId   = $EventLog.EventIdError
        }

        $context = $Entry.CmdletName
        if ($Entry.ProfileName) { $context += " Profile=$($Entry.ProfileName)" }
        if ($Entry.CAServer)    { $context += " CAServer=$($Entry.CAServer)" }

        $prefix = ''
        if ($Entry.Level -eq 'Debug') { $prefix = '[DEBUG] ' }
        $message = "$prefix[$($Entry.UserName)] [$context] $($Entry.Message)"

        Write-EventLog -LogName $EventLog.LogName -Source $EventLog.Source `
            -EntryType $entryType -EventId $eventId -Message $message
    } catch {
        if (-not $script:LoggingSinkFailed) {
            $script:LoggingSinkFailed = $true
            Write-Warning "Posh-Certutil event log logging failed and will be skipped for the rest of this session: $_"
        }
    }
}
