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