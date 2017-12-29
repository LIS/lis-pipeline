#!/usr/bin/env groovy

def PowerShellWrapper(psCmd) {
    psCmd = psCmd.replaceAll("\r", "").replaceAll("\n", "")
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"\$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

pipeline {
  parameters {
    string(defaultValue: "stable", description: 'Branch to be built', name: 'KERNEL_GIT_BRANCH')
    string(defaultValue: "stable", description: 'Branch label (stable or unstable)', name: 'KERNEL_GIT_BRANCH_LABEL')
    string(defaultValue: "ubuntu", description: 'OS type (ubuntu or centos)', name: 'OS_TYPE')
    string(defaultValue: "x2", description: 'How many cores to use', name: 'THREAD_NUMBER')
    string(defaultValue: "build_artifacts, publish_temp_artifacts, boot_test, publish_artifacts, validation, validation_functional, validation_perf, validation_functional_hyperv, validation_functional_azure, validation_perf_azure, validation_perf_hyperv",
           description: 'What stages to run', name: 'ENABLED_STAGES')
  }
  environment {
    KERNEL_ARTIFACTS_PATH = 'kernel-artifacts'
    UBUNTU_VERSION = '16'
    BUILD_PATH = '/mnt/tmp/kernel-build-folder'
    KERNEL_CONFIG = './Microsoft/config-azure'
    CLEAN_ENV = 'False'
    USE_CCACHE = 'True'
    AZURE_MAX_RETRIES = '60'
    BUILD_NAME = 'kernel'
  }
  agent {
    node {
      label 'meta_slave'
    }
  }
  stages {
          stage('Build Ubuntu') {
              when {
                expression { params.OS_TYPE == 'ubuntu' }
                expression { params.ENABLED_STAGES.contains('build_artifacts') }
              }
              agent {
                node {
                  label 'ubuntu_kernel_builder'
                }
              }
              steps {
                withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL',
                                                  variable: 'KERNEL_GIT_URL')]) {
                  sh '''#!/bin/bash
                    set -xe
                    echo "Building artifacts..."
                    pushd "$WORKSPACE/scripts/package_building"
                    JOB_KERNEL_ARTIFACTS_PATH="${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                    bash build_artifacts.sh \\
                        --git_url ${KERNEL_GIT_URL} \\
                        --git_branch ${KERNEL_GIT_BRANCH} \\
                        --destination_path ${JOB_KERNEL_ARTIFACTS_PATH} \\
                        --install_deps True \\
                        --thread_number ${THREAD_NUMBER} \\
                        --debian_os_version ${UBUNTU_VERSION} \\
                        --build_path ${BUILD_PATH} \\
                        --kernel_config ${KERNEL_CONFIG} \\
                        --clean_env ${CLEAN_ENV} \\
                        --use_ccache ${USE_CCACHE}
                    popd
                    '''
                    writeFile file: 'ARM_IMAGE_NAME.azure.env', text: 'Canonical UbuntuServer 16.04-LTS latest'
                    writeFile file: 'ARM_OSVHD_NAME.azure.env', text: "SS-AUTOBUILT-Canonical-UbuntuServer-16.04-latest-${BUILD_NAME}${BUILD_NUMBER}.vhd'"                    
                    writeFile file: 'KERNEL_PACKAGE_NAME.azure.env', text: 'testKernel.deb'
                }
                stash includes: '*.azure.env', name: 'azure.env'
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.KERNEL_ARTIFACTS_PATH}/msft*/deb/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
          }
          stage('Build CentOS') {
              when {
                expression { params.OS_TYPE == 'centos' }
                expression { params.ENABLED_STAGES.contains('build_artifacts') }
              }
              agent {
                node {
                  label 'centos_kernel_builder'
                }
              }
              steps {
                withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL')]) {
                  sh '''#!/bin/bash
                    set -xe
                    echo "Building artifacts..."
                    pushd "$WORKSPACE/scripts/package_building"
                    JOB_KERNEL_ARTIFACTS_PATH="${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                    bash build_artifacts.sh \\
                        --git_url ${KERNEL_GIT_URL} \\
                        --git_branch ${KERNEL_GIT_BRANCH} \\
                        --destination_path ${JOB_KERNEL_ARTIFACTS_PATH} \\
                        --install_deps True \\
                        --thread_number ${THREAD_NUMBER} \\
                        --debian_os_version ${UBUNTU_VERSION} \\
                        --build_path ${BUILD_PATH} \\
                        --kernel_config ${KERNEL_CONFIG} \\
                        --clean_env ${CLEAN_ENV} \\
                        --use_ccache ${USE_CCACHE}
                    popd
                    '''
                    writeFile file: 'ARM_IMAGE_NAME.azure.env', text: 'OpenLogic CentOS 7.3 latest'
                    writeFile file: 'ARM_OSVHD_NAME.azure.env', text: "SS-AUTOBUILT-OpenLogic-CentOS-7.3-latest-${BUILD_NAME}${BUILD_NUMBER}.vhd'"
                    writeFile file: 'KERNEL_PACKAGE_NAME.azure.env', text: 'testKernel.rpm'
                }
                stash includes: '*.azure.env', name: 'azure.env'
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.KERNEL_ARTIFACTS_PATH}/msft*/rpm/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
    }
    stage('Temporary Artifacts Publish') {
      when {
        expression { params.ENABLED_STAGES.contains('publish_temp_artifacts') }
      }
      agent {
        node {
          label 'meta_slave'
        }
      }
      steps {
        dir("${env.KERNEL_ARTIFACTS_PATH}" + env.BUILD_NUMBER) {
            unstash "${env.KERNEL_ARTIFACTS_PATH}"
            withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                               string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                               usernamePassword(credentialsId: 'smb_share_user_pass',
                                                passwordVariable: 'PASSWORD',
                                                usernameVariable: 'USERNAME')]) {
                sh '''#!/bin/bash
                    set -xe
                    MOUNT_POINT="/tmp/${BUILD_NUMBER}"
                    mkdir -p $MOUNT_POINT
                    sudo mount -t cifs "${SMB_SHARE_URL}/temp-kernel-artifacts" $MOUNT_POINT \
                               -o vers=3.0,username=${USERNAME},password=${PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp

                    JOB_KERNEL_ARTIFACTS_PATH="${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                    relpath_kernel_artifacts=$(realpath "scripts/package_building/${JOB_KERNEL_ARTIFACTS_PATH}")
                    sudo cp -rf "${relpath_kernel_artifacts}/msft"* $MOUNT_POINT

                    sudo umount $MOUNT_POINT
                '''
            }
        }
      }
    }
    stage('Boot Validation') {
      when {
        expression { params.ENABLED_STAGES.contains('boot_test') }
      }
      agent {
        node {
          label 'meta_slave'
        }
      }
      steps {
        withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                                   string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                                   usernamePassword(credentialsId: 'smb_share_user_pass', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')
                                   ]) {
          dir('kernel_version' + env.BUILD_NUMBER) {
            unstash 'kernel_version_ini'
            sh 'cat scripts/package_building/kernel_versions.ini'
          }
          sh '''
            bash scripts/azure_kernel_validation/validate_azure_vm_boot.sh \
                --build_name $BUILD_NAME --build_number $BUILD_NUMBER \
                --smb_share_username $USERNAME --smb_share_password $PASSWORD \
                --smb_share_url $SMB_SHARE_URL --vm_user_name $OS_TYPE \
                --os_type $OS_TYPE
            '''
        }

      }
      post {
        failure {
          sh 'echo "Load failure test results."'
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests-fail.xml')
        }
        success {
          echo "Cleaning Azure resources up..."
          sh '''#!/bin/bash
            pushd ./scripts/azure_kernel_validation
            bash remove_azure_vm_resources.sh "$BUILD_NAME$BUILD_NUMBER"
            popd
            '''
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests.xml')
        }
      }
    }
    stage('Validated Artifacts Publish') {
      when {
        expression { params.ENABLED_STAGES.contains('publish_artifacts') }
      }
      agent {
        node {
          label 'meta_slave'
        }
      }
      steps {
        dir("${env.KERNEL_ARTIFACTS_PATH}" + env.BUILD_NUMBER) {
            unstash "${env.KERNEL_ARTIFACTS_PATH}"
            withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                               string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                               usernamePassword(credentialsId: 'smb_share_user_pass', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')
                               ]) {
                sh '''#!/bin/bash
                    set -xe
                    MOUNT_POINT="/tmp/${BUILD_NUMBER}"
                    mkdir -p $MOUNT_POINT
                    sudo mount -t cifs "${SMB_SHARE_URL}/${KERNEL_GIT_BRANCH_LABEL}-kernels" $MOUNT_POINT \
                               -o vers=3.0,username=${USERNAME},password=${PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp

                    JOB_KERNEL_ARTIFACTS_PATH="${BUILD_NUMBER}-${KERNEL_ARTIFACTS_PATH}"
                    relpath_kernel_artifacts=$(realpath "scripts/package_building/${JOB_KERNEL_ARTIFACTS_PATH}")
                    sudo cp -rf "${relpath_kernel_artifacts}/msft"* $MOUNT_POINT

                    sudo umount $MOUNT_POINT
                '''
            }
        }
      }
    }
    stage('Publish Azure VHD') {
      when {
                expression { params.ENABLED_STAGES.contains('validation') }
                expression { params.ENABLED_STAGES.contains('azure') }
      }
      agent {
        node {
          label 'azure'
        }
      }
      steps {
        withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
          cleanWs()
          git "https://github.com/iamshital/azure-linux-automation.git"
          unstash "${env.KERNEL_ARTIFACTS_PATH}"
          unstash 'kernel_version_ini'
          unstash 'azure.env'
          script {
              env.ARM_IMAGE_NAME = readFile 'ARM_IMAGE_NAME.azure.env'
              env.KERNEL_PACKAGE_NAME = readFile 'KERNEL_PACKAGE_NAME.azure.env'
          }
          RunPowershellCommand('cat scripts/package_building/kernel_versions.ini')
          RunPowershellCommand(".\\RunAzureTests.ps1" +
          " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
          " -customKernel 'localfile:${KERNEL_PACKAGE_NAME}'" +
          " -testLocation 'northeurope'" +
          " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
          " -testCycle 'PUBLISH-VHD'" +
          " -OverrideVMSize 'Standard_DS1_v2'" +
          " -ARMImageName '${ARM_IMAGE_NAME}'" +
          " -StorageAccount 'ExistingStorage_Premium'"
          )              
        }
      }        
    }    
    stage('Functional Tests') {
     when {
      expression { params.ENABLED_STAGES.contains('validation') }
     }
     parallel {
      stage('LISA') {
          when {
            expression { params.ENABLED_STAGES.contains('validation_functional_hyperv') }
          }
          agent {
            node {
              label 'hyper-v'
            }
          }
          steps {
            withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                                       string(credentialsId: 'WIN_SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                                       usernamePassword(credentialsId: 'smb_share_user_pass',
                                                        passwordVariable: 'PASSWORD',
                                                        usernameVariable: 'USERNAME')]) {
                echo 'Running LISA...'
                dir('kernel_version' + env.BUILD_NUMBER) {
                    unstash 'kernel_version_ini'
                    PowerShellWrapper('cat scripts/package_building/kernel_versions.ini')
                }
                PowerShellWrapper('''
                    & ".\\scripts\\lis_hyperv_platform\\main.ps1"
                        -KernelVersionPath "kernel_version${env:BUILD_NUMBER}\\scripts\\package_building\\kernel_versions.ini"
                        -SharedStoragePath "${env:SMB_SHARE_URL}\\${env:KERNEL_GIT_BRANCH_LABEL}-kernels"
                        -ShareUser $env:USERNAME -SharePassword $env:PASSWORD
                        -JobId "${env:BUILD_NAME}${env:BUILD_NUMBER}"
                        -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}"
                        -VHDType $env:OS_TYPE -WorkingDirectory "C:\\workspace"
                        -IdRSAPub "C:\\bin\\id_rsa.pub"
                        -XmlTest KvpTests.xml
                  ''')
                echo 'Finished running LISA.'
              }
            }
          post {
            always {
              archiveArtifacts 'lis-test\\WS2012R2\\lisa\\TestResults\\**\\*'
              junit 'lis-test\\WS2012R2\\lisa\\TestResults\\**\\*.xml'
            }
            success {
              echo 'Cleaning up LISA environment...'
              PowerShellWrapper('''
                  & ".\\scripts\\lis_hyperv_platform\\tear_down_env.ps1" -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}"
                ''')
            }
          }
        }
        stage('Azure-Functional') {
          when {
            expression { params.ENABLED_STAGES.contains('validation_functional_azure') }
          }
          agent {
            node {
              label 'azure'
            }
          }
          steps {
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
              cleanWs()
              git "https://github.com/iamshital/azure-linux-automation.git"
              unstash "${env.KERNEL_ARTIFACTS_PATH}"
              unstash 'kernel_version_ini'
              unstash 'azure.env'
              script {
                  env.ARM_IMAGE_NAME = readFile 'ARM_IMAGE_NAME.azure.env'
                  env.ARM_OSVHD_NAME = readFile 'ARM_OSVHD_NAME.azure.env'
                  env.KERNEL_PACKAGE_NAME = readFile 'KERNEL_PACKAGE_NAME.azure.env'
              }
              RunPowershellCommand('cat scripts/package_building/kernel_versions.ini')
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -testLocation 'northeurope'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'BVTMK'" +
              " -OverrideVMSize 'Standard_D1_v2'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Standard'"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -testLocation 'westus'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'DEPLOYMENT'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Standard'"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -testLocation 'westus'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'DEPLOYMENT'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Premium'"
              )              
            }
          }
        }
        stage('Azure-Performance') {
          when {
            expression { params.ENABLED_STAGES.contains('validation_perf_azure') }
          }
          agent {
            node {
              label 'azure'
            }
          }
          steps {
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
              cleanWs()
              git "https://github.com/iamshital/azure-linux-automation.git"
              unstash "${env.KERNEL_ARTIFACTS_PATH}"
              unstash 'kernel_version_ini'
              unstash 'azure.env'
              script {
                  env.ARM_IMAGE_NAME = readFile 'ARM_IMAGE_NAME.azure.env'
                  env.ARM_OSVHD_NAME = readFile 'ARM_OSVHD_NAME.azure.env'
                  env.KERNEL_PACKAGE_NAME = readFile 'KERNEL_PACKAGE_NAME.azure.env'
              }
              RunPowershellCommand('cat scripts/package_building/kernel_versions.ini')
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +              
              " -testLocation 'westus2'" +             
              " -testCycle 'PERF-LAGSCOPE'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -ResultDBTable 'Perf_Network_Latency_Azure_MsftKernel'" +
              " -ResultDBTestTag 'LAGSCOPE-TEST'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -EnableAcceleratedNetworking"              
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-IPERF3-SINGLE-CONNECTION'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_Single_TCP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'IPERF-SINGLE-CONNECTION-TEST'" +
              " -EnableAcceleratedNetworking"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-NTTTCP'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_TCP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'NTTTCP-SRIOV'" +
              " -EnableAcceleratedNetworking"     
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +              
              " -testLocation 'westus2'" +             
              " -testCycle 'PERF-LAGSCOPE'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -ResultDBTable 'Perf_Network_Latency_Azure_MsftKernel'" +
              " -ResultDBTestTag 'LAGSCOPE-TEST'" +
              " -StorageAccount 'ExistingStorage_Standard'"             
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-IPERF3-SINGLE-CONNECTION'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_Single_TCP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'IPERF-SINGLE-CONNECTION-TEST'"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-NTTTCP'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_TCP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'NTTTCP-SRIOV'"  
              )    
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -customKernel 'localfile:${KERNEL_PACKAGE_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -ARMImageName '${ARM_IMAGE_NAME}'" +              
              " -testLocation 'centralus'" +             
              " -testCycle 'PERF-FIO'" +
              " -RunSelectedTests 'ICA-PERF-FIO-TEST-4K'" + 
              " -OverrideVMSize 'Standard_DS14_v2'" +
              " -ResultDBTable 'Perf_Storage_Azure_MsftKernel'" +
              " -ResultDBTestTag 'FIO-12DISKS'" +
              " -StorageAccount 'NewStorage_Premium'"             
              )                                 
            }
          }
        }
        stage('Performance On Hyper-V') {
          when {
            expression { params.ENABLED_STAGES.contains('validation_perf_hyperv') }
          }
          agent {
            node {
              label 'meta_slave'
            }
          }
          steps {
            echo "NOOP Hyper-V Performance test."
          }
        }
      }
    }
  }
}
