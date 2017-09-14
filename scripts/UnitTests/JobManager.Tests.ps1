$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentPath = Split-Path -Parent $here
. "$parentPath\JobManager.ps1"

Describe "Test Job Manager Success" {

    Mock Write-Host -Verifiable {return}

    $jobManager = [PSJobManager]::new()
    $topic = "fake_topic"
    $jobManager.AddJob($topic, {Write-Output "fake_output";start-sleep 2;Write-Output "fake_1"}, @(), $null)
    $jobManager.WaitForJobsCompletion($topic, 10)
    $errors = $JobManager.GetJobErrors($topic)
    $results = $JobManager.GetJobOutputs($topic)
    $JobManager.RemoveTopic($topic)

    It "Should run all jobs successfully" {
        $errors | Should Be 0
    }

    It "Should output the correct string" {
        $results | Should Be $null
    }
    

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}

Describe "Test Job Manager Fail" {

    Mock Write-Host -Verifiable {return}

    $jobManager = [PSJobManager]::new()
    $topic = "fake_topic"
    $jobManager.AddJob($topic, {Write-Output "fake_output";start-sleep 2;Write-Output "fake_1"}, @(), $null)
    $jobManager.WaitForJobsCompletion($topic, 1)
    $errors = $JobManager.GetJobErrors($topic)
    $results = $JobManager.GetJobOutputs($topic)
    $JobManager.RemoveTopic($topic)

    It "Should run all jobs successfully" {
        $errors | Should Be 1
    }

    It "Should output the correct string" {
        $results | Should Be "fake_output"
    }
    

    It "should run all mocked commands" {
        Assert-VerifiableMocks
    }
}
