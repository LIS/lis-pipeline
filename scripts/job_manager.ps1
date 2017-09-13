<#
.SYNOPSIS

Class to ease PowerShell Job management

You can add a PowerShell Job to a Topic. A Topic is a label for a set of
jobs that you want to manage in the same way (start, stop, wait).

You can easily manipulate a single Job by adding it to a unique Topic.
#>
class PSJobManager {
    [String] $Name = "PSJobManager"
    [Hashtable] $Jobs = @{}
    [Array] $StartingStates = @([System.Management.Automation.JobState]::NotStarted)
    [Array] $RunningStates = @([System.Management.Automation.JobState]::AtBreakpoint,
                               [System.Management.Automation.JobState]::Blocked,
                               [System.Management.Automation.JobState]::Disconnected,
                               [System.Management.Automation.JobState]::Running,
                               [System.Management.Automation.JobState]::Stopping,
                               [System.Management.Automation.JobState]::Suspended,
                               [System.Management.Automation.JobState]::Suspending)
    [Array] $FinishedStates = @([System.Management.Automation.JobState]::Completed,
                                [System.Management.Automation.JobState]::Failed,
                                [System.Management.Automation.JobState]::Stopped)

    JobManager () {
    }

    <#
    .SYNOPSIS

    Creates a Job and adds it to a Topic.
    #>
    [void] AddJob ($Topic, $ScriptBlock, $ArgumentList, $InitScript) {
        $job = Start-Job -ScriptBlock $ScriptBlock `
                         -ArgumentList $ArgumentList `
                         -InitializationScript $InitScript
        $timeout = 10
        while ($timeout -gt 0) {
            if ($job.State -in $this.RunningStates) {
                break;
            } else {
                Start-Sleep 1
                $timeout -= 1
            }
        }
        if ($job.State -eq [System.Management.Automation.JobState]::Completed) {
            Write-Host "Job Completed"
            $this.Jobs[$Topic].AddLast($job)
        } elseif ($job.State -eq [System.Management.Automation.JobState]::Failed) {
            Write-Host "Job failed to start" -ForegroundColor Red
            $output = Receive-Job -Job $job -Keep
            $state = $job.State
            Remove-Job -Job $job
            Write-host "Job with state: $state failed with output `r`n$output`r`n" -ForegroundColor Red
        } elseif ($job.State -eq [System.Management.Automation.JobState]::Stopped){
            Write-Host "Job is Stopped, adding it to the Topic"
            $this.Jobs[$Topic].AddLast($job)
        } elseif ($this.Jobs.Contains($Topic)) {
            $this.Jobs[$Topic].AddLast($job)
        } else {
            $this.Jobs[$Topic] = New-Object Collections.Generic.LinkedList[object]
            $this.Jobs[$Topic].AddLast($job)
        }
    }

    <#
    .SYNOPSIS

    Removes all jobs in the Topic and finally removes the topic itself.
    #>
    [void] RemoveTopic ($Topic) {
        Write-Host "Removing jobs from topic: $Topic"
        $current = $this.Jobs[$Topic].First
        while (-not ($current -eq $null)) {
            $timeout = 5
            while ($Timeout -gt 0) {
                try {
                    Remove-Job $current.Value -Force
                    $timeout = 0
                } catch {
                    Start-Sleep 1
                    $timeout -= 1
                }
            }
            $current = $current.Next
        }
        $this.Jobs.Remove($Topic)
    }

    [Collections.Generic.LinkedList[object]] GetJobsFromTopic ($Topic) {
        if ($this.Jobs.Contains($Topic)) {
            return $this.Jobs[$Topic]
        } else {
            Write-Host "No Topic with $Topic name found."
            return $null
        }
    }
    
    [Array] WaitForJobsCompletion ($Topic, $Timeout) {
        Write-Host "Waiting for jobs completion"
        $statuses = @()
        $current = $this.Jobs[$Topic].First
        $jobTimeout = $Timeout
        while (-not ($current -eq $null)) {
            $status = [System.Management.Automation.JobState]::Running
            $Timeout =  $jobTimeout
            $jobTimeout = $Timeout
            while (($status -in $this.RunningStates) -and ($jobTimeout -gt 0)) {
                if ($current.Value.State -in $this.RunningStates) {
                    Write-Host ("Waiting for job {0} to finish, remaining time: {1}" -f @($current.Value.Name, $jobTimeout))
                    $status = $current.Value.State
                    Start-Sleep 1
                    $jobTimeout -= 1
                } else {
                    $statuses += $current.Value.State
                    break
                }
            }
            $current = $current.Next
        }
        return $statuses
    }

    <#
    .SYSNOPSIS

    Job results for the specified Topic.
    #>
    [Array] GetJobOutputs ($Topic) {
        Write-Host "Retrieving Output from Jobs in Topic: $Topic"
        $results = @()
        $current = $this.Jobs[$Topic].First
        while(-not ($current -eq $null)) {
            $result = $current.Value | Receive-Job -Keep -ErrorAction SilentlyContinue
            $results += $result 
            $current = $current.Next
        }
        return $results
    }
    
    <#
    .SYSNOPSIS

    Job errors for the specified Topic.
    #>
    [Array] GetJobErrors($Topic) {
        Write-Host "Retrieving Output from Jobs in Topic: $Topic"
        $states = 0
        $current = $this.Jobs[$Topic].First
        while(-not ($current -eq $null)) {
            if ($current.Value.State -ne [System.Management.Automation.JobState]::Completed) {
                $states += 1
                Write-Host ("Job {0} failed." -f @($current.Value.Name))
            }
            $current = $current.Next
        }
        return $states
    }
}
