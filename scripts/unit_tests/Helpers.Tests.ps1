$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path -Parent $here
$moduleName = "helpers"
Import-Module "$parentPath\utils\powershell\helpers.psm1"

Describe "Test valid Parse-IcaLog" {
    Mock -CommandName Get-Content -ModuleName $moduleName  -Verifiable -MockWith {return "Test Results Summary"}

    It "Should parse a valid ica log" {
        $results = Parse-IcaLog -IcaLogPath "fake_path"
        $results | Should Be 0
    }

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}

Describe "Test valid Parse-IcaLog no-zero" {
    Mock -CommandName Get-Content -ModuleName $moduleName  -Verifiable -MockWith {return "    Test : Failed"}
    Mock Write-Host -ModuleName $moduleName -Verifiable {return}

    It "Should parse a valid ica log" {
        $results = Parse-IcaLog -IcaLogPath "fake_path"
        $results | Should Be 1
    }

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}

Describe "Test no valid Parse-IcaLog" {
    Mock Get-Content -ModuleName $moduleName -Verifiable {return "Test results summar"}
    Mock Write-Host -ModuleName $moduleName -Verifiable {return}

    It "Should parse a valid ica log" {
        { Parse-IcaLog -IcaLogPath "fake_path"} | Should Throw
    }

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}
