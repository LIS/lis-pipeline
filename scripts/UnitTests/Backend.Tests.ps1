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

Describe "Test Azure Backend Instance" {
    Mock Write-Verbose -Verifiable {return}
    Mock login_azure -Verifiable {return}
    Mock Stop-AzureRmVM -Verifiable {return}
    Mock Remove-AzureRmVM -Verifiable {return}
    Mock Get-AzureRmNetworkSecurityGroup -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]::new() }
    Mock Get-AzureRmPublicIpAddress -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress]::new()}
    Mock Get-AzureRmVirtualNetwork -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]::new() }
    Mock Get-AzureRmVirtualNetworkSubnetConfig -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSSubnet]::new()}
    Mock New-AzureRmVMConfig -Verifiable {return [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]::new()}
    Mock Get-AzureRmNetworkInterface -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]::new()}
    Mock Set-AzureRmNetworkInterface -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]::new()}
    Mock Get-AzureRmVM -Verifiable {return [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]::new()}
    Mock Add-AzureRmVMNetworkInterface -Verifiable {return [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]::new()}

    $backendFactory = [BackendFactory]::new()
    $fake_name = "test"
    $fake_useIPW = "yes"
    $fake_image_name = "123456789012345678901234567890123"
    It "Should test Backend Factory " {
        $backendFactory | Should Not Be $null
    }
    $azureBackend = $backendFactory.GetBackend("AzureBackend",@(1))

    It "Should test instance wrapper" {
        $azureInstance =  $azureBackend.GetInstanceWrapper($fake_name)
        $azureInstance  | Should Not Be $null
    }
    It "Should test azure instance" {
        $newInstance = [AzureInstance]::new($this,$fake_image_ame)
        $newInstance | Should Not Be $null
    }
    It "Should test Setup Azure RG" {
        $SetupAzureRG = $azureBackend.SetupAzureRG()
        $SetupAzureRG | Should  Be $true
    }
    It "Should test wait for azure RG"{
        $WaitForAzureRG = $azureBackend.WaitForAzureRG()
        $WaitForAzureRG | Should Be  "Success"
    }

    It "Should test stop instance" {
        $StopInstance = $azureBackend.StopInstance($fake_name)
        $StopInstance | Should Not Be $false
    }
    It "Should test remove instance" {
        $RemoveInstance = $azureBackend.RemoveInstance($fake_name)
        $RemoveInstance | Should Not Be $false
    }
    It "Should test cleanup instance" {
        $CleanupInstance = $azureBackend.CleanupInstance($fake_name)
        $CleanupInstance | Should  Be $null
    }
    It "Should test get public ip" {
        $GetPublicIP = $azureBackend.GetPublicIP($fake_name)
        $GetPublicIP | Should Not Be $null
    }
    It "Should test get PSSession"{
        $GetPSSession = $azureBackend.GetPSSession($fake_name)
        $GetPSSession | Should Not Be $false
    }
    It "Should test GetVM" {
        $GetVM  = $azureBackend.GetVM($fake_name)
        $GetVM  | Should Not Be $null
    }
    It "Should test create instance from specialized"{
        $CreateInstanceFromSpecialized = $azureBackend.CreateInstanceFromSpecialized($fake_name)
        $CreateInstanceFromSpecialized | Should Not Be $false
    }
    It "Should run all mocked commands" {
         Assert-VerifiableMocks
    }
}
