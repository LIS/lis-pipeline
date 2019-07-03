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

return this