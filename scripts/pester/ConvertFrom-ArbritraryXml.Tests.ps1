# $here = Split-Path -Parent $MyInvocation.MyCommand.Path
# $sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
# . "$here\$sut"

Import-Module ..\ConvertFrom-ArbritraryXml.psm1

Describe "ConvertFrom-JSON -- Simple Case" {
    ####################################################################################################################
    ####################################################################################################################
    It "Generates simple JSON baseline for validation" {
        $PSObject = New-Object PSObject
        $PSObject | Add-Member -NotePropertyName "Name" -NotePropertyValue "Top"
#        InnerXml:"<Property Name="Name" Type="System.String">Top</Property>"
#       TODO: Hmm.
        $result_simple_case = $PSObject | ConvertTo-Json
        $xml_simple_case = $PSObject | ConvertTo-Xml
        $true | Should Be $true
    }
    ####################################################################################################################
    ####################################################################################################################
    It "Verify Simple XML" {
        $simple="
<TOP>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow

        $convertedJSON = $SomeCrazyType | ConvertTo-Json 
        #$stripSpaceAndReturns = $convertedJSON.Replace(" ","")

        $convertedJSON | Should Be @'
{
    "TOP":  {

            }
}
'@
    }
    ####################################################################################################################
    ####################################################################################################################
    It "Simple Nested XML" {
        $simple="
<TOP>
  <Child/>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow
        $testValue = $SomeCrazyType | ConvertTo-Json
        $testValue | Should Be @'
{
    "TOP":  {
                "Child":  ""
            }
}
'@
    }
    ####################################################################################################################
    ####################################################################################################################
    It "One double-nested child -- [depth 5] XML" {
      $simple="
<TOP>
<Middle>
<Child>
  <Name>Alan</Name>
</Child>
</Middle>
</TOP>
"
      $xml = [xml] $simple
      # Write-Host $xml -ForegroundColor Green
      $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
      # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
      # Write-Host $foo -ForegroundColor Yellow
      $testValue = $SomeCrazyType | ConvertTo-Json -Depth 5
      $testValue | Should Be @'
{
    "TOP":  {
                "Middle":  {
                               "Child":  {
                                             "Name":  "Alan"
                                         }
                           }
            }
}
'@
  }
    ####################################################################################################################
    ####################################################################################################################
    It "One double-nested child -- XML" {
      $simple="
<TOP>
<Middle>
<Child>
  <Name>Alan</Name>
</Child>
</Middle>
</TOP>
"
      $xml = [xml] $simple
      # Write-Host $xml -ForegroundColor Green
      $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
      # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
      # Write-Host $foo -ForegroundColor Yellow
      $testValue = $SomeCrazyType | ConvertTo-Json
      $testValue | Should Be @'
{
    "TOP":  {
                "Middle":  {
                               "Child":  "@{Name=Alan}"
                           }
            }
}
'@
  }  
    ####################################################################################################################
    ####################################################################################################################
    It "One nested child -- XML" {
      $simple="
<TOP>
<Child>
  <Name>Alan</Name>
</Child>
</TOP>
"
      $xml = [xml] $simple
      # Write-Host $xml -ForegroundColor Green
      $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
      # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
      # Write-Host $foo -ForegroundColor Yellow
      $testValue = $SomeCrazyType | ConvertTo-Json
      $testValue | Should Be @'
{
    "TOP":  {
                "Child":  {
                              "Name":  "Alan"
                          }
            }
}
'@
  }    
    ####################################################################################################################
    ####################################################################################################################
    It "Two nested children -- XML" {
        $simple="
<TOP>
  <Child>
    <Name>Alan</Name>
  </Child>
  <Child>
    <Name>Beth</Name>
  </Child>
</TOP>
"
        $xml = [xml] $simple
        # Write-Host $xml -ForegroundColor Green
        $SomeCrazyType = ConvertFrom-ArbritraryXml ( $xml )
        # $foo = $SomeCrazyType | ConvertTo-Json -Depth 3
        # Write-Host $foo -ForegroundColor Yellow
        $testValue = $SomeCrazyType | ConvertTo-Json
        $testValue | Should Be @'
{
    "TOP":  {
                "Child":  [
                              "@{Name=Alan}",
                              "@{Name=Beth}"
                          ]
            }
}
'@
    }
}
