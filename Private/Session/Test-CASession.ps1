function Test-CASession {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )

    # Invoke-Command will throw for any broken/closed state, so no need to pre-check State.
    try {
        Invoke-Command -Session $Session -ScriptBlock { $true } -ErrorAction Stop | Out-Null
        $true
    } catch {
        $false
    }
}
