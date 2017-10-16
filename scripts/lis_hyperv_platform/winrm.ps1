param(
    [String] $SharedStoragePath = "\\10.7.13.118\lava",
    [String] $JobId = "64",
    [String] $ConfigDrivePath = "C:\path\to\configdrive\",
    [String] $UserdataPath = "C:\path\to\userdata.sh",
    [String] $KernelURL = "kernel_url",
    [String] $MkIsoFS = "C:\path\to\mkisofs.exe",
    [String] $InstanceName = "Instance1",
    [String] $KernelVersion = "4.13.2",
    [String] $SecretsPath = "C:\path\to\secrets.ps1",
    [Int] $VMCheckTimeout = 200
   )

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$command = ("& $scriptPath\main.ps1 " `
           + "-SharedStoragePath $SharedStoragePath " `
           + "-JobId $JobId " `
           + "-UserDataPath $UserdataPath -KernelURL $KernelURL -MkIsoFS $MkIsoFS " `
           + "-InstanceName $InstanceName -KernelVersion $KernelVersion -VMCheckTimeout $VMCheckTimeout")

echo $command
. $SecretsPath
$random = get-random 10000
$task_name = "WinRM_Elevated_Shell-$random" 
$out_file = "$env:SystemRoot\Temp\WinRM_Elevated_Shell-$random.log"

if (Test-Path $out_file) {
  del $out_file
}

$task_xml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <UserId>{user}</UserId>
      <LogonType>Password</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>4</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd</Command>
      <Arguments>{arguments}</Arguments>
    </Exec>
  </Actions>
</Task>
'@

$bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
$encoded_command = [Convert]::ToBase64String($bytes)
$arguments = "/c powershell.exe -EncodedCommand $encoded_command &gt; $out_file 2&gt;&amp;1"

$task_xml = $task_xml.Replace("{arguments}", $arguments)
$task_xml = $task_xml.Replace("{user}", $user)

$schedule = New-Object -ComObject "Schedule.Service"
$schedule.Connect()
$task = $schedule.NewTask($null)
$task.XmlText = $task_xml
$folder = $schedule.GetFolder("\")
$folder.RegisterTaskDefinition($task_name, $task, 6, $user, $password, 1, $null) | Out-Null

$registered_task = $folder.GetTask("\$task_name")
$registered_task.Run($null) | Out-Null

$timeout = 10
$sec = 0
while ( (!($registered_task.state -eq 4)) -and ($sec -lt $timeout) ) {
  Start-Sleep -s 1
  $sec++
}

# Read the entire file, but only write out new lines we haven't seen before
$numLinesRead = 0
do {
  Start-Sleep -m 100
  
  if (Test-Path $out_file) {
    $text = (get-content $out_file)
    $numLines = ($text | Measure-Object -line).lines    
    $numLinesToRead = $numLines - $numLinesRead
    
    if ($numLinesToRead -gt 0) {
      $text | select -first $numLinesToRead -skip $numLinesRead | ForEach {
        #Write-Host "$_"
      }
      $numLinesRead += $numLinesToRead
    }
  }
} while (!($registered_task.state -eq 3))
start-sleep -m 100
if (Test-Path $out_file) {
    $text = (Get-Content $out_file)
    foreach ($line in $text) {
        if ((!$line.contains("<Obj")) -or $line.contains("<<<")) {
            Write-Host $line
        }
    }
  }

$exit_code = $registered_task.LastTaskResult
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($schedule) | Out-Null
exit $exit_code
