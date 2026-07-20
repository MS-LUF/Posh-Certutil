function Get-CACulture {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session
    )
    # certutil -view csv writes date/time columns in the CA server's own locale, not the
    # admin machine's — the culture name must come from the CA to parse those dates correctly.
    Invoke-Command -Session $Session -ScriptBlock { (Get-Culture).Name } -ErrorAction Stop
}
