function Get-CALocalDate {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Runspaces.PSSession] $Session,
        [Parameter(Mandatory)] [int] $Days
    )
    # Compute date strings on the CA server using the CA's locale and timezone,
    # which is what certutil -view -restrict date comparisons use.
    Invoke-Command -Session $Session -ScriptBlock {
        param($D)
        @{
            Today      = (Get-Date).ToString('d')
            ExpireDate = (Get-Date).AddDays($D).ToString('d')
        }
    } -ArgumentList $Days
}
