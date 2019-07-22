#!/usr/bin/env groovy

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}


def isJobCronTriggered() {
    for (cause in currentBuild.rawBuild.getCauses()) {
        if (cause != null) {
            def causeDescription = cause.getShortDescription()
            if (causeDescription && causeDescription.contains("Started by timer")) {
                return true
            }
        }
    }
    return false
}


def GetTestResults(type) {
    withEnv(["Type=${type}"]) {
        def returnValues = powershell returnStdout: true, script: '''
            $file = Get-Item ".\\Report\\*-junit.xml" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc | select -Last 1
            if (!$file) {
                return 0
            }
            $content = [xml](Get-Content $file)
            $failCase = [int]($content.testsuites.testsuite.failures)
            $allCase = [int]($content.testsuites.testsuite.tests)
            $abortCase = [int]($content.testsuites.testsuite.errors)
            $skippedCase = [int]($content.testsuites.testsuite.skipped)
            $passCase = $allCase - $failCase - $abortCase - $skippedCase

            if ($env:Type -eq "pass") {
                return $passCase
            } elseif ($env:Type -eq "abort") {
                return $abortCase
            } elseif ($env:Type -eq "fail") {
                return $failCase
            } elseif ($env:Type -eq "skipped") {
                return $skippedCase
            } elseif ($env:Type -eq "all") {
                return $allCase
            }
        '''
        return "${returnValues}"
    }
}


return this