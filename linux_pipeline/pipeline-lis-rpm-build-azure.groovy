// Wrapper to execute powershell scripts / commands
def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

def CopyBuildFiles(destination)
{
    //unstash the *.pbuild and ips.sh files
    unstash 'LISISO_PBUILD'
    unstash 'LISISO_IP'
    sh (returnStdout: true, script: """
        yes | cp RH5.pbuild ${destination}/rh5/pbuild/.pbuild --force;
        yes | cp RH6.pbuild ${destination}/rh6/pbuild/.pbuild --force;
        yes | cp RH7.pbuild ${destination}/rh7/pbuild/.pbuild --force;
        dos2unix ${destination}/ips.sh;
        dos2unix ${destination}/rh5/pbuild/.pbuild;
        dos2unix ${destination}/rh6/pbuild/.pbuild;
        dos2unix ${destination}/rh7/pbuild/.pbuild;
        """)
}

node ("meta_slave") {
    try {

    stage ("Prerequisite") {
        // Copy the LISAv2 code to jenkins
        cleanWs()
        git "https://github.com/LIS/LISAv2.git"
        stash includes: '**', name: 'LISAv2'
        cleanWs()

        // Get the required data from config file.
        withCredentials([file(credentialsId: 'LIS_HOTFIX_CONFIGURE_FILE', variable: 'LIS_HOTFIX_CONFIGURE_FILE')]) {
            sh (returnStatus: true, script: """#!/bin/bash
            . ${LIS_HOTFIX_CONFIGURE_FILE}
            echo -n "\$LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT" > LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT.tmp
            echo -n "\$LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY" > LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY.tmp
            """ )
        }
        env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT = readFile 'LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT.tmp'
        env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY = readFile 'LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY.tmp'
    }

    stage ('Generate Build Files') {
        node('azure') {
            git branch: "${build_rpm_source_branch}", url: "${build_rpm_source}"
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
                RunPowershellCommand(".\\CreatePBuild-IP-Files.ps1"+
                                " -ResourceGroupName '${RESOURCE_GROUP_NAME}'" +
                                " -secretsFile '${Azure_Secrets_File}' "
                                )
            }
            stash includes: '*.pbuild', name: 'LISISO_PBUILD'
            stash includes: 'ips.sh', name: 'LISISO_IP'
        }
    }

    stage ('Build RPM') {
        def Distros = [:]
        if( ( distro == 'all') || ( distro == 'rh5')) {
            Distros["RH5"] = {
                node('lisbuilddemo') {
                    try {
                        stage ('RH5') {
                            cleanWs()
                            git branch: "${build_rpm_source_branch}", url: "${build_rpm_source}"
                            println WORKSPACE
                            CopyBuildFiles("${WORKSPACE}")
                            sh "cd ${WORKSPACE};  python createrpms.py rh5 ${buildname} ${source} --branch ${branch}"
                        }
                    }
                    catch (exc) {
                        currentBuild.result = 'FAILURE'
                        println "${it}: STAGE_FAILED_EXCEPTION."
                        sh "exit 1"
                    }
                }
            }
        }
        if( ( distro == 'all') || ( distro == 'rh6')) {
            Distros["RH6"] = {
                node('lisbuilddemo') {
                    try {
                        stage ('RH6') {
                            cleanWs()
                            git branch: "${build_rpm_source_branch}", url: "${build_rpm_source}"
                            CopyBuildFiles("${WORKSPACE}")
                            sh "cd ${WORKSPACE};  python createrpms.py rh6 ${buildname} ${source} --branch ${branch}"
                        }
                    }
                    catch (exc)  {
                        currentBuild.result = 'FAILURE'
                        println "${it}: STAGE_FAILED_EXCEPTION."
                        sh "exit 1"
                    }
                }
            }
        }
        if( ( distro == 'all') || ( distro == 'rh7')) {
            Distros["RH7"] =  {
                node("lisbuilddemo") {
                    try {
                        stage ('RH7') {
                            cleanWs()
                            git branch: "${build_rpm_source_branch}", url: "${build_rpm_source}"
                            CopyBuildFiles("${WORKSPACE}")
                            sh "cd ${WORKSPACE}; python createrpms.py rh7 ${buildname} ${source} --branch ${branch}"
                        }
                    }
                    catch (exc) {
                        currentBuild.result = 'FAILURE'
                        println "${it}: STAGE_FAILED_EXCEPTION."
                        sh "exit 1"
                    }
                }
            }
        }
        parallel Distros
    }

    stage ("Copy/Publish RPM's") {
        node('lis-rpm-build-controller-vm') {
            cleanWs()
            git branch: "${build_rpm_source_branch}", url: "${build_rpm_source}"
            unstash 'LISISO_IP'
            def cmdline = "today=`date +%Y-%m-%d.%H.%M` ; cd ${WORKSPACE} ; dos2unix ips.sh; ./copyall.sh ; tar -cvzf lis-rpm-${buildname}-" + '${today}' + ".tar.gz LISISO"
            println cmdline
            def cmdline1 = "today=`date +%Y-%m-%d.%H.%M` ; cd ${WORKSPACE} ;  dos2unix ips.sh; ./copyall.sh ; mkisofs -r -iso-level 4 -o lis-rpm-${buildname}-" + '${today}' + ".iso LISISO"
            sh "${cmdline}"
            sh "${cmdline1}"
            stash includes: '*.tar.gz', name: 'lisrpmtarball'
            stash includes: '*.iso', name: 'lisrpmiso'
        }
        node ('azure') {
            cleanWs()
            unstash 'LISAv2'
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
                unstash 'lisrpmtarball'
                unstash 'lisrpmiso'
                RunPowershellCommand("Set-Variable -Name LogDir -Value '.' -Scope Global; Set-Variable -Name LogFileName -Value 'UploadFiles.log.txt' -Scope Global;" +
                '$LIS_RPM_URL = ' +  ".\\Utilities\\UploadFilesToStorageAccount.ps1" +
                ' -filePaths $((Get-ChildItem "*.tar.gz").Name)'  +
                " -destinationStorageAccount '${env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT}'" +
                " -destinationStorageKey '${env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY}'" +
                " -destinationContainer lis-rpm-builds" +
                " -destinationFolder 'lis-builds'" +
                '; Set-Content -Value $LIS_RPM_URL -Path LIS_RPM_DOWNLOAD_URL.azure.env -Force -NoNewline' +
                '; Write-Host $LIS_RPM_URL' +
                '; Set-Content -Path LIS_RPM_URL.txt -Value $LIS_RPM_URL -Force -Verbose -NoNewline'
                )
                RunPowershellCommand("Set-Variable -Name LogDir -Value '.' -Scope Global; Set-Variable -Name LogFileName -Value 'UploadFiles.log.txt' -Scope Global;" +
                '$LIS_ISO_URL = ' +  ".\\Utilities\\UploadFilesToStorageAccount.ps1" +
                ' -filePaths $((Get-ChildItem "*.iso").Name)'  +
                " -destinationStorageAccount '${env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT}'" +
                " -destinationStorageKey '${env.LIS_RPM_BUILD_PUBLISH_STORAGE_ACCOUNT_KEY}'" +
                " -destinationContainer lis-rpm-builds" +
                " -destinationFolder 'lis-builds'" +
                '; Write-Host $LIS_ISO_URL; '  +
                '; Set-Content -Path LIS_ISO_URL.txt -Value $LIS_ISO_URL -Force -Verbose -NoNewline'
                )
                archiveArtifacts 'LIS_RPM_URL.txt'
                archiveArtifacts 'LIS_ISO_URL.txt'
                stash includes: '*.azure.env', name: 'azure.env'
            }
        }
    }

    allImages = testDistros.split("\n")
    def testImages = []
    def currentImageArr = ""
    def currentDistroVersion = ""
    allImages.each
    {
        currentImageArr = "${it}".split(" ")
        currentDistroVersion = currentImageArr[2]
        if ( currentDistroVersion.startsWith("6") && distro == 'rh6')
        {
            testImages.add("${it}")
        }
        if ( currentDistroVersion.startsWith("7") && distro == 'rh7')
        {
            testImages.add("${it}")
        }
        if ( distro == 'all')
        {
            testImages.add("${it}")
        }
    }

    stage("Smoke tests")  {
        ARMImage = [:]
        testImages.each  {
            ARMImage["${it}"] = {
                try {
                    stage ("${it}") {
                        node('azure') {
                            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
                                cleanWs()
                                echo "Current Image: ${it}"
                                unstash 'azure.env'
                                unstash 'LISAv2'
                                env.LIS_DOWNLOAD_URL = readFile 'LIS_RPM_DOWNLOAD_URL.azure.env'
                                RunPowershellCommand(".\\Run-LisaV2.ps1" +
                                " -TestLocation 'southcentralus'" +
                                " -RGIdentifier 'RPMBUILD-${BUILD_NUMBER}'" +
                                " -TestPlatform  'Azure'" +
                                " -ARMImageName '${it}'" +
                                " -CustomLIS '${LIS_DOWNLOAD_URL}'" +
                                " -TestNames 'VERIFY-DEPLOYMENT-PROVISION,LIS-DRIVER-VERSION-CHECK'" +
                                " -StorageAccount 'ExistingStorage_Standard'" +
                                " -XMLSecretFile '${Azure_Secrets_File}'" +
                                " -CustomParameters 'DiskType=Managed'" +
                                " -ExitWithZero" +
                                " -EnableTelemetry"
                                )
                                junit "Report\\*-junit.xml"
                                archiveArtifacts '*-TestLogs.zip'
                            }
                        }
                    }
                }
                catch (exc) {
                    currentBuild.result = 'FAILURE'
                    println "${it}: STAGE_FAILED_EXCEPTION."
                }
            }
        }
        parallel ARMImage
    }
} catch (exc) {
        currentBuild.result = 'FAILURE'
        def exc_string = exc.toString()
        println exc_string
    }
}
