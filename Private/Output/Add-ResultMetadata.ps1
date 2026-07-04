function Add-ResultMetadata {
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [object] $InputObject,
        [Parameter(Mandatory)] [string] $Profile,
        [Parameter(Mandatory)] [string] $CAServer
    )

    process {
        $InputObject |
            Add-Member -MemberType NoteProperty -Name 'Profile'  -Value $Profile  -Force -PassThru |
            Add-Member -MemberType NoteProperty -Name 'CAServer' -Value $CAServer -Force -PassThru
    }
}
