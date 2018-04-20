$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path -Parent $here
. "$parentPath\utils\powershell\Backend.ps1"

function Get-VMHardDiskDrive {}

Describe "Test Hyper-V Backend instance" {
    Mock Write-Warning -Verifiable {return}
    Mock Get-VMHardDiskDrive -Verifiable {return}
    $backendFactory = [BackendFactory]::new()
    $hypervBackend = $backendFactory.GetBackend("HypervBackend", @(""))
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
    Mock Get-AzureRmNetworkInterface -Verifiable {$VNIC=[Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]::new()
        $VNIC.Id=1
        return $VNIC
    }
    Mock Set-AzureRmVMOSDisk -Verifiable {return $vm}
    Mock Set-AzureRmNetworkInterface -Verifiable {return [Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]::new()}
    Mock Get-AzureRmVM -Verifiable {return [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]::new()}
    Mock Add-AzureRmVMNetworkInterface -Verifiable {return [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]::new()}
    Mock Write-Error -Verifiable {return}
    Mock Stop-Transcript -Verifiable {return}
    Mock Set-AzureRmVMSourceImage -Verifiable { return $vm }
    Mock Set-AzureRmVMOperatingSystem -Verifiable {return $vm }

    $backendFactory = [BackendFactory]::new()
    $azureBackend = $backendFactory.GetBackend("AzureBackend",@(1))
    $fake_name = "test"
    $fake_useIPW = "yes"
    $fake_image_name = "123456789012345678901234567890123"

    It "Should test Backend Factory " {
        $backendFactory | Should Not Be $null
    }

    It "Should test instance wrapper" {
        $azureInstance =  $azureBackend.GetInstanceWrapper($fake_name)
        $azureInstance  | Should Not Be $null
    }

    It "Should test azure instance" {
        $newInstance = [AzureInstance]::new($this,$fake_image_name)
        $newInstance | Should Not Be $null
    }

    It "Should test Setup Azure RG" {
        $setupAzureRG = $azureBackend.SetupAzureRG()
        $setupAzureRG | Should  Be $true
    }

    It "Should test wait for Azure RG" {
        $waitForAzureRG = $azureBackend.WaitForAzureRG()
        $waitForAzureRG | Should Be  "Success"
    }

    It "Should test Stop Instance" {
        $stopInstance = $azureBackend.StopInstance($fake_name)
        $stopInstance | Should Not Be $false
    }

    It "Should test Remove Instance" {
        $removeInstance = $azureBackend.RemoveInstance($fake_name)
        $removeInstance | Should Not Be $false
    }

    It "Should test Cleanup Instance" {
        $cleanupInstance = $azureBackend.CleanupInstance($fake_name)
        $cleanupInstance | Should  Be $null
    }

    It "Should test Get Public Ip" {
        $getPublicIP = $azureBackend.GetPublicIP($fake_name)
        $getPublicIP | Should Not Be $null
    }

    It "Should test Get PSSession" {
        $getPSSession = $azureBackend.GetPSSession($fake_name)
        $getPSSession | Should Not Be $false
    }

    It "Should test Get VM" {
        $getVM  = $azureBackend.GetVM($fake_name)
        $getVM  | Should Not Be $null
    }

    It "Should test Get NSG" {
        $getNSG = $azureBackend.getNSG()
        $getNSG | Should Not Be $null
    }

    It "Should test Get Network" {
        $getNetwork = $azureBackend.getNetwork($sg)
        $getNetwork | Should Not Be $null
    }

    It "Should test Get Subnet" {
        $vmvnetObject =[Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]::new()
        $getSubnet = $azureBackend.getSubnet($sg, $vmvnetObject)
        $getSubnet | Should Not Be $null
    }

    It "Should test Get Pip Name" {
        $fake_pip_name = "pip"
        $getpip = $azureBackend.getPIP($fake_pip_name)
        $getpip | Should Not Be $null
    }

    It "Should test Get NIC" {
        $fake_nic_name = "nic"
        $getNIC = $azureBackend.getNIC($fake_nic_name, $VMSubnetObject, $pip)
        $getNIC | Should Not Be $null
    }

    It "Should test Create Instance from Specialized" {
        $createInstanceFromSpecialized = $azureBackend.CreateInstanceFromSpecialized($fake_name)
        $createInstanceFromSpecialized | Should Not Be $false
    }

    Mock make_cred_initial -Verifiable {
        $fake_user_passwd = "passwd"
        $fake_user_name = "user"
        $fakePassword = ConvertTo-SecureString -AsPlainText -Force -String "$fake_user_passwd" 
        $fakeCred = New-Object -TypeName System.Management.Automation.PSCredential -Argumentlist "$fake_user_name", $fakePassword
        return $fakeCred
    }

    It "Should test Create Instance from URN" {
        $azureBackend.blobURN = "test:test:test:2"
        $createInstanceFromURN = $azureBackend.CreateInstanceFromURN($fake_name, $fake_useIPW)
        $createInstanceFromURN | Should Not Be $false 
    }

    It "Should test Create Instance from Generalized" {
        $createInstanceFromGeneralized = $azureBackend.CreateInstanceFromGeneralized($fake_name, $fake_useIPW)
        $createInstanceFromGeneralized | Should Not Be $false
    }

    It "Should run all mocked commands" {
       Assert-VerifiableMocks
    }
}