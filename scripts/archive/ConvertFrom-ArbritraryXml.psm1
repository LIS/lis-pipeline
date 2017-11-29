Function ConvertFrom-ArbritraryXml( $Object )
{
  $originalObject = $null
  if ($null -ne $Object ) 
  {
    if( ($null -ne $Object.DocumentElement))
    {
      # Get to the document element.  We will use this for recursion.
       $originalObject = $Object
       $Object = $Object.DocumentElement
    } 
    $PSObject = New-Object PSObject
    $documentName = $Object.LocalName
    foreach( $child in $Object.ChildNodes )
    {
        $inner = $child.InnerXml
        if( $inner.StartsWith( "<" ) -and $inner.EndsWith( ">") )
        {
            # Recurse (TODO: DEPTH) to form the type.
            $childObject = ConvertFrom-ArbritraryXml $child
            $array = @()
            $array = $($PSObject.$($child.LocalName))
            if( ($null -ne $array ) -and !(($array -is [array])) )
            {
              $array = @($array)
            }
            $array += $childObject
            $PSObject | Add-Member -NotePropertyName $child.LocalName -NotePropertyValue $array -Force
        }
        else {
           $PSObject | Add-Member -NotePropertyName $child.LocalName -NotePropertyValue $child.InnerXml
        }
    }
    if( $null -ne $originalObject )
    {
      $returnValue = New-Object PSObject
      $returnValue | Add-Member -NotePropertyName $documentName -NotePropertyValue $PSObject
      $returnValue
    }
    else {
      $PSObject    
    }
  }
}