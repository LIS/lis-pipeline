class Const {

    $ec2Json = ' {
        "reservation-id":  "r-yze3jupp",
        "hostname":  "cloudbase",
        "security-groups":  [

                            ],
        "public-ipv4":  "",
        "ami-manifest-path":  "FIXME",
        "instance-type":  "windowsoff",
        "instance-id":  "i-00000039",
        "local-ipv4":  "10.0.0.50",
        "local-hostname":  "v4.novalocal",
        "placement":  {
                          "availability-zone":  "nova"
                      },
        "ami-launch-index":  0,
        "public-hostname":  "v4.novalocal",
        "public-keys":  {
                            "0":  {
                                      "openssh-key":  "",
                                      "_name":  "0=userkey"
                                  }
                        },
        "ami-id":  "ami-00000008",
        "instance-action":  "none",
        "block-device-mapping":  {
                                     "ami":  "vda",
                                     "root":  "/dev/vda"
                                 }
    }'

    $openstackJson = '{
        "admin_pass":  "Ah2v75Kf9fxW",
        "random_seed":  "egvf0lwQHzuSghLdeUAr8HSf2b4EoKW7wAKBV+0LuH4PD6Ub37ahB47mOg0iWrc1QaXutTULziLy1wVzCX1Grrj3lSEbEIoLrrFv0WPJ7wTpnDibu8q/09bxgd4983W25DtY6lX4mefiaMJ1JHkWFckdynBM7EHfaEFJgOgsbjbhdYvgIz1GOvzD9Y44t3IfuXeNu1kFzBAdrPoD/BxjLYE7SKs9rBMcg746+Lzl7DDSRKb4TO6Wo7HEUPS1hV+0h/tdcx54uVPNHi4CDcW2ML/qin3C97jlL9ZcsBqmMAIuLO1XOy/Y0YNK3pyPiqwr1A4Ci0BXblQiwVTIFqU9HkpDkLubEm16DSPDeE9GfcI47G+tToERe4iRoHrtoYxUZeFtXmTxzLJGXqnV1pNrWY2YTVUS0NNOha90VSMM8YzOP6qwEdTqq9xxtk/c6k3raQ88lxGl2sD5vDDJOZRa8H2iZ6B8OzZYqcW0Xvob6ev8hX7+GQjf99Up20MqnkVtibaNY2BKiRfkKrBXheMd2nxW644gnMb9yD3OSwrKpO5c0gavS/mphbWOifvUChy76Ok3DZqgUrGnwoGghx0fws6OnjWfc1i63ftU6qWxXqWDdt/V0aPk9BFmYxIo9DcU5f0jDac0B10H9S8TYnhNmApnOQjNN+gPId/ttfzHGGM=",
        "uuid":  "b9517879-4e93-4a1a-9073-4ae0ddfac27c",
        "availability_zone":  "nova",
        "keys":  [
                     {
                         "data":  "",
                         "type":  "ssh",
                         "name":  "userkey"
                     }
                 ],
        "hostname":  "cloudbase",
        "launch_index":  0,
        "public_keys":  {
                            "userkey":  ""
                        },
        "project_id":  "25e716490a9948c4870246beaab24329",
        "name":  "cloudbase"
    }'

    $userdata = '
#!/bin/bash

exit 0'
}

class Node {
    [String] $Name
    [Object] $Properties
    [Node] $Parent
    [Node[]] $Children

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
            $Root.Children += $node
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
        foreach ($node in $Root.Children) {
            $this.TreeTraversal($node)
        }
    }

    [void] WrapperRemakeStructure ($Root) {
        New-Item -ItemType "directory" -Path $Root.Name -ErrorAction SilentlyContinue
        pushd $Root.Name
        foreach ($child in $Root.Children) {
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
    
    ConfigDrive ($Name) {
        $this.Name = $Name
    }

    [void] GetProperties ($Path) {
        if ($Path) {
            $root = [Node]::new($Path)
            $this.DirectoryTree = [Tree]::new($root)
            $this.DirectoryTree.GenerateTree($root)
        } else {
            $const = [Const]::new()
            $root = [Node]::new("cloud")
            $this.DirectoryTree = [Tree]::new($root)

            $ec2 = [Node]::new("ec2"); $ec2.Parent = $root
            $openstack = [Node]::new("openstack"); $openstack.Parent = $root
            $root.Children = @($ec2, $openstack)

            $latest1 = [Node]::new("latest"); $latest1.Parent = $ec2
            $d20090404 = [Node]::new("2009-04-04"); $d20090404.Parent = $ec2
            $ec2.Children = @($latest1, $d20090404)

            $latest2 = [Node]::new("latest"); $latest2.Parent = $openstack
            $d20151015 = [Node]::new("2015-10-15"); $d20151015.Parent = $openstack
            $d20131017 = [Node]::new("2013-10--17"); $d20131017.Parent = $openstack
            $openstack.Children = @($latest2, $d20151015, $d20131017)

            $ec2Metadata = [Node]::new("meta-data.json"); $ec2Metadata.Parent = $openstack
            $ec2Metadata.Properties = $const.ec2Json | ConvertFrom-Json
            $ec2Userdata = [Node]::new("user-data"); $ec2Userdata.Parent = $openstack
            $ec2Userdata.Properties = $const.userdata
            $latest1.Children = @($ec2Metadata, $ec2Userdata)
            $d20090404.Children = @($ec2Metadata, $ec2Userdata)

            $openstackMetadata =[Node]::new("meta_data.json"); $openstackMetadata.Parent = $openstack
            $openstackMetadata.Properties = $const.openstackJson | ConvertFrom-Json
            $openstackUserdata =[Node]::new("user_data"); $openstackMetadata.Parent = $openstack
            $openstackUserdata.Properties = $const.userdata
            $latest2.Children = @($openstackMetadata, $openstackUserdata)
            $d20151015.Children = @($openstackMetadata, $openstackUserdata)
            $d20131017.Children = @($openstackMetadata, $openstackUserdata)

            $this.DirectoryTree.Leaves = @($ec2Metadata, $ec2Userdata, $openstackMetadata, $openstackUserdata)
        }
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
