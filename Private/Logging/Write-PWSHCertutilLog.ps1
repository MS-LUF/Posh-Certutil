function Write-PWSHCertutilLog {
    <#
    .SYNOPSIS
        Writes a log entry to the configured logging destination (file or Windows Event Log).
    .DESCRIPTION
        Central logging entry point called by every public cmdlet. Reads and normalizes the
        Logging section of the configuration, filters by MinimumLevel, and dispatches to
        Write-FileLogEntry or Write-EventLogEntry depending on Mode. Every entry is stamped
        with the Windows identity of the user running the command, so audit trails can always
        be linked back to who ran the action — not just what CA/profile it targeted.

        When -BoundParameters is supplied, its keys/values are appended to the message with
        Credential/Password/Secret/Token-named parameters redacted, so secrets never reach a
        log file or the Windows Event Log. Callers typically pass this only on the Debug-level
        entry-point log for each cmdlet invocation.

        No-ops silently when logging is disabled (Logging.Enabled = $false, the default for
        configs that predate this feature) or when Level is below the configured
        MinimumLevel. Never throws — a logging failure must never break the cmdlet's actual
        certutil/certreq work.
    .PARAMETER Config
        The parsed configuration object returned by Read-ConfigFile.
    .PARAMETER Level
        Severity of this entry: Debug, Information, Warning, or Error.
    .PARAMETER Message
        The log message.
    .PARAMETER CmdletName
        Name of the calling cmdlet, e.g. $MyInvocation.MyCommand.Name.
    .PARAMETER ProfileName
        Optional. The config profile involved in this action.
    .PARAMETER CAServer
        Optional. The CA server involved in this action.
    .PARAMETER BoundParameters
        Optional. $PSBoundParameters of the calling cmdlet; appended to the message with
        sensitive values redacted.
    .EXAMPLE
        Write-PWSHCertutilLog -Config $config -Level Debug -CmdletName $MyInvocation.MyCommand.Name -Message 'Cmdlet invoked' -BoundParameters $PSBoundParameters
        Logs cmdlet entry with its bound parameters (secrets redacted) at Debug level.
    .EXAMPLE
        Write-PWSHCertutilLog -Config $config -Level Information -CmdletName 'Get-PWSHCertutilIssuedCerts' -ProfileName 'prod-pki' -CAServer 'ca01.corp.local' -Message 'Retrieved 12 issued certificate(s)'
        Logs a one-line summary of a successful operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject] $Config,

        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $CmdletName,

        [Parameter()]
        [string] $ProfileName,

        [Parameter()]
        [string] $CAServer,

        [Parameter()]
        [hashtable] $BoundParameters
    )

    try {
        $loggingConfig = Get-LoggingConfig -Config $Config
        if (-not $loggingConfig.Enabled) { return }

        $minimumSeverity = $script:LogLevelSeverity[$loggingConfig.MinimumLevel]
        $entrySeverity   = $script:LogLevelSeverity[$Level]
        if ($entrySeverity -lt $minimumSeverity) { return }

        $fullMessage = $Message
        if ($BoundParameters) {
            $redacted = foreach ($key in ($BoundParameters.Keys | Sort-Object)) {
                if ($key -match 'Credential|Password|Secret|Token') {
                    "$key=<redacted>"
                } else {
                    "$key=$($BoundParameters[$key])"
                }
            }
            $fullMessage = "$Message ($($redacted -join '; '))"
        }

        $entry = [PSCustomObject]@{
            Timestamp   = Get-Date
            Level       = $Level
            UserName    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            CmdletName  = $CmdletName
            ProfileName = $ProfileName
            CAServer    = $CAServer
            Message     = $fullMessage
        }

        if ($loggingConfig.Mode -eq 'EventLog') {
            Write-EventLogEntry -EventLog $loggingConfig.EventLog -Entry $entry
        } else {
            Write-FileLogEntry -File $loggingConfig.File -Entry $entry
        }
    } catch {
        if (-not $script:LoggingSinkFailed) {
            $script:LoggingSinkFailed = $true
            Write-Warning "Posh-Certutil logging failed and will be skipped for the rest of this session: $_"
        }
    }
}
