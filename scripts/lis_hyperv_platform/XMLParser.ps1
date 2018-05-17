class XMLParser {
    [String] $Name
    [Xml] $XML

    XMLParser ([String] $Path) {
        $this.XML = Get-Content -Path $Path
    }

    [void] SelectTestsContain ([String] $Value) {
        # this is for the suiteTest only
        $suites = $this.XML.config.testSuites.suite.suiteTests.InnerXML
        $suites = $suites.Replace("><", "> <")
        [System.Collections.ArrayList] $testSuites = $suites.Split(" ")
        [System.Collections.ArrayList] $forTests = $suites.Split(" ")
        foreach ($test in $forTests) {
            if (-not($test.Contains($Value))) {
                $testSuites.Remove($test)
            }
        }
        $innerXML = $testSuites.Replace(" ", "")
        $this.XML.config.testSuites.suite.suiteTests.InnerXML = $innerXML

        $testCases = $this.XML.config.testCases
        $tests = $this.XML.config.testCases.ChildNodes
        [System.Collections.ArrayList] $list = @()
        foreach ($test in $tests) {
            if (-not($test.testName -like "*$Value*")) {
                $list.Add($test)
            }
        }
        foreach ($element in $list) {
            $testCases.RemoveChild($element)
        }
    }

    [void] ChangeParam([String] $Name, [String] $Value) {
        $params = $this.XML.config.testCases.test.testParams
        foreach ($param in $params.ChildNodes) {
            if ($param.InnerText -like "*$Name*") {
                $param.InnerText = "$Name=($Value)"
            }
        }
    }

    [String] CheckKey([String] $Key) {
        $tests = $this.XML.config.testSuites.suite.suiteTests.InnerXML
        $params = $this.XML.config.testCases.test.testParams.InnerXML

        $return = "none"

        if ($tests.Contains($Key)) {
            $return = "test"
        # let the quotes around params. this way we treat it as a string not as an array
        } elseif ("$params".Contains($Key))  {
            $return = "param"
        }
        return $return
    }

    [void] ChangeXML([String] $Option) {
        $key = $Option.Split("=")[0]
        $value = $Option.Split("=")[1]

        $type = $this.CheckKey($key)
        switch ($type) {
            "test"  {$this.SelectTestsContain($key)} 
            "param" {$this.ChangeParam($key, $value)}
        }

    }

    [void] InsertInstallKernel () {
        $testSuite = "<suiteTest>Install_MSFT_Kernel</suiteTest>"
        $test = "<test>" +
                "<testName>Install_MSFT_kernel</testName>" +
                "<testScript>SetupScripts\install_kernel_rpm.ps1</testScript>" +
                "<files>remote-scripts/ica/utils.sh</files>" +
                "<timeout>2500</timeout>" +
                "<OnError>Abort</OnError>" +
                "<noReboot>False</noReboot>" +
                "</test>"
        $origInnerXML = $this.XML.config.testSuites.suite.suiteTests.InnerXml
        $newInnerXML = "$testSuite$origInnerXML"
        $this.XML.config.testSuites.suite.suiteTests.InnerXml = $newInnerXML

        $origInnerXML = $this.XML.config.testCases.InnerXml
        $newInnerXML = "$test$origInnerXML"
        $this.XML.config.testCases.InnerXml = $newInnerXML
    }

    [void] InsertCheckpoint () {
        $testSuite = "<suiteTest>MainVM_Checkpoint</suiteTest><suiteTest>DependencyVM_Checkpoint</suiteTest>"
        $test = """
    <test>
        <testName>MainVM_Checkpoint</testName>
        <testScript>setupscripts\PreVSS_TakeSnapshot.ps1</testScript>
        <timeout>600</timeout>
        <testParams>
            <param>TC_COVERED=snapshot</param>
            <param>snapshotVm=main</param>
            <param>snapshotName=ICABase</param>
        </testParams>
        <onError>Abort</onError>
        <noReboot>False</noReboot>
    </test>
    <test>
        <testName>DependencyVM_Checkpoint</testName>
        <testScript>setupscripts\PreVSS_TakeSnapshot.ps1</testScript>
        <timeout>600</timeout>
        <testParams>
            <param>TC_COVERED=snapshot</param>
            <param>snapshotVm=dependency</param>
            <param>snapshotName=ICABase</param>
        </testParams>
        <onError>Continue</onError>
        <noReboot>False</noReboot>
    </test>
"""

        $origInnerXML = $this.XML.config.testSuites.suite.suiteTests.InnerXml
        $newInnerXML = "$testSuite$origInnerXML"
        $this.XML.config.testSuites.suite.suiteTests.InnerXml = $newInnerXML

        $origInnerXML = $this.XML.config.testCases.InnerXml
        $newInnerXML = "$test$origInnerXML"
        $this.XML.config.testCases.InnerXml = $newInnerXML
    }

    [void] InsertCreateVM () {
        $global = "<defaultSnapshot>ICABase</defaultSnapshot>" +
                  "<LisaInitScript>" +
                  "<file>.\setupScripts\CreateVMs.ps1</file>" +
                  "</LisaInitScript>" +
                  "<imageStoreDir>\\unc\path</imageStoreDir>"

        $origInnerXML = $this.XML.config.global.InnerXml
        $newInnerXML = "$global$origInnerXML"
        $this.XML.config.global.InnerXml = $newInnerXML
    }

    [void] ChangeVM ([String] $VMSuffix) {
        $index = 0
        if ($this.XML.config.VMs.vm -is [array]) {
            foreach ($vmDef in $this.XML.config.VMs.vm) {
                $this.XML.config.VMS.vm[$index].vmName = $vmDef.vmName + $VMSuffix
                $testParams = $vmDef.testParams
                if ($testParams) {
                    $paramIndex = 0
                    foreach ($testParam in $testParams.param) {
                        if ($testParam -like "VM2NAME=*") {
                            $testParams.ChildNodes.Item($paramIndex)."#text" = `
                                $testParam + $VMSuffix
                        }
                        $paramIndex = $paramIndex + 1
                    }
                }
                $index = $index + 1
            }
        } else {
            $this.XML.config.VMS.vm.vmName = $this.XML.config.VMS.vm.vmName + $VMSuffix
        }
    }

    [XML] ReturnXML () {
        return $this.XML
    }

    [void] Save ([String] $Path) {
        if (Test-Path -Path $Path) {
            $path = Resolve-Path -Path $Path
        }
        $this.XML.Save($path)
    }
}
