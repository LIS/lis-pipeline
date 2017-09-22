class Node {
    [String] $Name
    [Object] $Properties
    [Node] $Parent
    [Node[]] $Childs

    Node ($Name) {
        $this.Name = $Name
    }

    [String] ToString () {
        return $this.Name
    }
}

class Tree {
    [String] $Name
    [Node] $Root
    [Node[]] $Leaves

    Tree ($Node) {
        $this.Root = $Node
    }

    [void] GenerateTree ($Root) {
        pushd $Root.Name
        foreach ($item in Get-ChildItem) {
            $node = [Node]::new($item)
            $node.Parent = $Root
            $Root.Childs += $node
            if ($item -is [System.IO.DirectoryInfo]) {
                $this.GenerateTree($node)
            } elseif ($item.Extension -eq ".json" ) {
                $node.Properties = $this.GetJson($item)
                $this.Leaves += $node
            } elseif ($item.Name -eq "user-data" -or
                      $item.Name -eq "user_data") {
                $node.Properties = Get-Content -Raw -Path $item
                $this.Leaves += $node
            }
        }
        popd
    }

    [Object] GetJson ($File) {
        $customHashtable = Get-Content -Raw -Path $File | ConvertFrom-Json
        return $customHashtable
    }

    [void] TreeTraversal ($Root) {
        Write-Host $Root.Name
        Write-Host $Root.Properties
        foreach ($node in $Root.Childs) {
            $this.TreeTraversal($node)
        }
    }

    [void] WrapperRemakeStructure ($Root) {
        New-Item -ItemType "directory" -Path $Root.Name -ErrorAction SilentlyContinue
        pushd $Root.Name
        foreach ($child in $Root.Childs) {
            if ($child.Name -like "*.json") {
                $child.Properties | ConvertTo-Json -Compress | Set-Content $child.Name -NoNewLine
            } elseif (
                $child.Name -eq "user_data" -or
                $child.Name -eq "user-data") {
                $child.Properties | Set-Content -Path $child.Name
            } else {
                $this.WrapperRemakeStructure($child)
            }
        }
        popd
    }

    [void] RemakeStructure ($NewPath) {
        $tree = $this
        $tree.Root.Name = $NewPath
        $this.WrapperRemakeStructure($tree.Root)
    }

    [Array] GetLeaves () {
        return $this.Leaves
    }

    [String] ToString () {
        return $this.Root.Name
    }
}

class ConfigDrive {
    [String] $Name
    [String] $Path
    [Array] $JsonFiles
    [Tree] $DirectoryTree
    
    ConfigDrive ($Name, $Path) {
        $this.Name = $Name
        $this.Path = $Path
    }

    [void] GetProperties () {
        $root = [Node]::new($this.Path)
        $this.DirectoryTree = [Tree]::new($root)
        $this.DirectoryTree.GenerateTree($root)
    }

    [void] ChangeProperty ($Key, $Value) {
        $leaves = $this.DirectoryTree.GetLeaves()
        foreach ($leaf in $leaves) {
            if ($leaf.Properties.$Key) {
                $leaf.Properties.$Key = $Value
            }
        }
    }

    [void] ChangeUserData ($File) {
        $content = Get-Content -Raw -Path $File
        $leaves = $this.DirectoryTree.GetLeaves()
        foreach ($leaf in $leaves) {
            if ($leaf.Name -eq "user_data" -or
                $leaf.Name -eq "user-data") {
                $leaf.Properties = $content
            }
        }
    }

    [void] ChangeSSHKey ($File) {
        $key = Get-Content -Raw -Path $File
        $leaves = $this.DirectoryTree.GetLeaves()
        foreach ($leaf in $leaves) {
            if ($leaf.Name -eq "meta-data.json") {
                $leaf.Properties.'public-keys'.'0'.'openssh-key' = $key.ToString()
            } elseif ($leaf.Name -eq "meta_data.json") {
                $leaf.Properties.public_keys.userkey = $key.ToString()
            }
        }
    }

    [void] SaveToNewConfigDrive ($NewPath) {
        $this.DirectoryTree.RemakeStructure($NewPath)
    }

    [void] Print () {
        $this.DirectoryTree.TreeTraversal($this.DirectoryTree.Root)
    }
}
