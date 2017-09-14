$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path -Parent $here
. "$parentPath\Backend.ps1"

Describe "Test Hyper-V Backend instance" {
    Mock Write-Warning -Verifiable {return}
    $backendFactory = [BackendFactory]::new()
    $hypervBackend = $backendFactory.GetBackend("HypervBackend", @(1))
    $vmName = "fake_vm_name"
    It "Should create a valid instance wrapper" {
        $hypervInstance = $hypervBackend.GetInstanceWrapper($vmName)
        $hypervInstance | Should Not Be $null
    }

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}
