function Test-EventSourceExists {
    <#
    .SYNOPSIS
        Returns whether a Windows Event Log source is already registered.
    .DESCRIPTION
        Thin wrapper around [System.Diagnostics.EventLog]::SourceExists(), extracted into its
        own function so Write-EventLogEntry's source-creation branch can be unit tested with a
        mock instead of depending on real Windows Event Log state or elevation.
    .PARAMETER Source
        The event source name to check.
    .OUTPUTS
        Boolean.
    .EXAMPLE
        Test-EventSourceExists -Source 'Posh-Certutil'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Source
    )

    [System.Diagnostics.EventLog]::SourceExists($Source)
}
