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
            $this.Jobs[$Topic] += $job
        } elseif ($job.State -eq [System.Management.Automation.JobState]::Failed) {
            Write-Host "Job failed to start" -ForegroundColor Red
            $output = Receive-Job -Job $job -Keep
            $state = $job.State
            Remove-Job -Job $job -Force
            Write-host "Job with state: $state failed with output `r`n$output`r`n" -ForegroundColor Red
        } elseif ($job.State -eq [System.Management.Automation.JobState]::Stopped){
            Write-Host "Job is Stopped, adding it to the Topic"
            $this.Jobs[$Topic] += $job
        } elseif ($this.Jobs.Contains($Topic)) {
            $this.Jobs[$Topic] += $job
        } else {
            $this.Jobs[$Topic] = @()
            $this.Jobs[$Topic] += $job
        }
    }

    <#
    .SYNOPSIS

    Removes all jobs in the Topic and finally removes the topic itself.
    #>
    [void] RemoveTopic ($Topic) {
        Write-Host "Removing jobs from topic: $Topic"
        foreach ($job in $this.Jobs[$Topic]) {
            Remove-Job $job -Force
        }
        $this.Jobs.Remove($Topic)
    }

    [Array] GetJobsFromTopic ($Topic) {
        if ($this.Jobs.Contains($Topic)) {
            return $this.Jobs[$Topic]
        } else {
            Write-Host "No topic with $Topic name found."
            return $null
        }
    }

    [void] WaitForJobsCompletion ($Topic, $Timeout) {
        Write-Host "Waiting for jobs completion..."
        $jobsCount = $this.Jobs[$Topic].Count
        while ($Timeout -ne 0 -and $jobsCount -ne 0) {
            $jobsCount = 0
            foreach ($job in $this.Jobs[$Topic]) {
                if ($job.State -in $this.RunningStates) {
                    Write-Host ("Waiting for job {0} to finish, remaining time: {1}" -f @($job.Name, $Timeout))
                    $jobsCount += 1
                }
                $output = $this.GetJobOutput($job.Name)
                if ($output) {
                    Write-Host ("Current output for job {0} >> {1}" -f @($job.Name, $output))
                }
            }
            Start-Sleep 1
            $Timeout -= 1
        }
    }

    <#
    .SYSNOPSIS

    Job results for the specified Topic.
    #>
    [String] GetJobOutput ($JobName) {
        return (Receive-Job -Name $JobName -ErrorAction SilentlyContinue)
    }

    <#
    .SYSNOPSIS

    Job results for the specified Topic.
    #>
    [Array] GetJobOutputs ($Topic) {
        Write-Host "Retrieving output of jobs for $Topic"
        $results = @()
        foreach ($job in $this.Jobs[$Topic]) {
            $result = Receive-Job $job -ErrorAction SilentlyContinue
            $results += $result 
        }
        return $results
    }

    <#
    .SYSNOPSIS

    Get the number of failed jobs for the specified Topic.
    #>
    [int] GetJobErrors($Topic) {
        Write-Host "Retrieving the number of failed jobs for $Topic..."
        $errors = 0
        foreach ($job in $this.Jobs[$Topic]) {
            if ($job.State -ne [System.Management.Automation.JobState]::Completed) {
                $errors += 1
                Write-Host ("Job {0} failed." -f @($job.Name))
            }
        }
        return $errors
    }
}
