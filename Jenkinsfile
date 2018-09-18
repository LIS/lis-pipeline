#!/usr/bin/env groovy

def PowerShellWrapper(psCmd) {
    psCmd = psCmd.replaceAll("\r", "").replaceAll("\n", "")
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"\$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

def reportStageStatus(stageName, stageStatus) {
    script {
        env.STAGE_NAME_REPORT = stageName
        env.STAGE_STATUS_REPORT = stageStatus
    }
    withCredentials(bindings: [file(credentialsId: 'KERNEL_QUALITY_REPORTING_DB_CONFIG',
                                    variable: 'PERF_DB_CONFIG')]) {
        dir('kernel_version_report' + env.BUILD_NUMBER + env.BRANCH_NAME) {
              unstash 'kernel_version_ini'
              sh '''#!/bin/bash
                  bash "${WORKSPACE}/scripts/reporting/report_stage_state.sh" \
                      --pipeline_name "pipeline-msft-kernel-validation/${BRANCH_NAME}" \
                      --pipeline_build_number "${BUILD_NUMBER}" \
                      --pipeline_stage_status "${STAGE_STATUS_REPORT}" \
                      --pipeline_stage_name "${STAGE_NAME_REPORT}" \
                      --kernel_info "./scripts/package_building/kernel_versions.ini" \
                      --kernel_source "MSFT" --kernel_branch "${KERNEL_GIT_BRANCH}" \
                      --distro_version "${DISTRO_VERSION}" --db_config ${PERF_DB_CONFIG} || true
              '''
        }
    }
}

pipeline {
  parameters {
    string(defaultValue: "stable", description: 'Branch to be built', name: 'KERNEL_GIT_BRANCH')
    string(defaultValue: "stable", description: 'Branch label (stable or unstable)', name: 'KERNEL_GIT_BRANCH_LABEL')
    choice(choices: 'Ubuntu_16.04.5\nCentOS_7.4', description: 'Distro version.', name: 'DISTRO_VERSION')
    choice(choices: "kernel_pipeline_bvt.xml\nkernel_pipeline_fvt.xml\ntest_kernel_pipeline.xml", description: 'Which tests should LISA run', name: 'LISA_TEST_XML')
    choice(choices: 'False\nTrue', description: 'Enable kernel debug', name: 'KERNEL_DEBUG')
    string(defaultValue: "build_artifacts, publish_temp_artifacts, boot_test, publish_artifacts, publish_vhd, publish_azure_vhd, publish_hyperv_vhd, validation_functional_hyperv, validation_functional_jessie_hyperv, validation_functional_azure, validation_perf_azure, validation_perf_hyperv",
           description: 'What stages to run', name: 'ENABLED_STAGES')
  }
  environment {
    KERNEL_ARTIFACTS_PATH = 'kernel-artifacts'
    UBUNTU_VERSION = '16'
    BUILD_PATH = '/mnt/tmp/kernel-build-folder'
    KERNEL_CONFIG = 'Microsoft/config-azure'
    CLEAN_ENV = 'False'
    USE_CCACHE = 'True'
    AZURE_MAX_RETRIES = '60'
    BUILD_NAME = 'm'
    FOLDER_PREFIX = 'msft'
    THREAD_NUMBER = 'x3'
    AZURE_LINUX_AUTOMATION_REPO = "https://github.com/LIS/azure-linux-automation.git"
  }
  options {
    overrideIndexTriggers(false)
  }
  agent {
    node {
      label 'meta_slave'
    }
  }
  stages {
          stage('build_artifacts_ubuntu') {
              when {
                beforeAgent true
                expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
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
                  stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                  sh '''#!/bin/bash
                    set -xe
                    echo "Building artifacts..."
                    pushd "$WORKSPACE/scripts/package_building"
                    bash build_artifacts.sh \\
                        --git_url "${KERNEL_GIT_URL}" \\
                        --git_branch "${KERNEL_GIT_BRANCH}" \\
                        --destination_path "${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}" \\
                        --install_deps "True" \\
                        --thread_number "${THREAD_NUMBER}" \\
                        --debian_os_version "${UBUNTU_VERSION}" \\
                        --build_path "${BUILD_PATH}" \\
                        --kernel_config "${KERNEL_CONFIG}" \\
                        --clean_env "${CLEAN_ENV}" \\
                        --use_ccache "${USE_CCACHE}" \\
                        --enable_kernel_debug "${KERNEL_DEBUG}"
                    popd
                    '''
                    writeFile file: 'ARM_IMAGE_NAME.azure.env', text: 'Canonical UbuntuServer 16.04-LTS latest'
                    writeFile file: 'ARM_OSVHD_NAME.azure.env', text: "SS-AUTOBUILT-Canonical-UbuntuServer-16.04-LTS-latest-${BUILD_NAME}${BUILD_NUMBER}.vhd"
                    writeFile file: 'KERNEL_PACKAGE_NAME.azure.env', text: 'testKernel.deb'
                }
                sh '''#!/bin/bash
                  echo ${BUILD_NUMBER}-$(crudini --get scripts/package_building/kernel_versions.ini KERNEL_BUILT folder) > ./build_name
                '''
                script {
                  currentBuild.displayName = readFile "./build_name"
                }
                stash includes: '*.azure.env', name: 'azure.env'
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/msft*/deb/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
              post {
                success {
                  reportStageStatus("BuildSucceeded", 1)
                }
                failure {
                  reportStageStatus("BuildSucceeded", 0)
                }
              }
          }
          stage('build_artifacts_centos') {
              when {
                beforeAgent true
                expression { params.DISTRO_VERSION.toLowerCase().contains('centos') }
                expression { params.ENABLED_STAGES.contains('build_artifacts') }
              }
              agent {
                node {
                  label 'centos_kernel_builder'
                }
              }
              steps {
                withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL')]) {
                  stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                  sh '''#!/bin/bash
                    set -xe
                    echo "Building artifacts..."
                    pushd "$WORKSPACE/scripts/package_building"
                    bash build_artifacts.sh \\
                        --git_url "${KERNEL_GIT_URL}" \\
                        --git_branch "${KERNEL_GIT_BRANCH}" \\
                        --destination_path "${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}" \\
                        --install_deps "True" \\
                        --thread_number "${THREAD_NUMBER}" \\
                        --build_path "${BUILD_PATH}" \\
                        --kernel_config "${KERNEL_CONFIG}" \\
                        --clean_env "${CLEAN_ENV}" \\
                        --use_ccache "${USE_CCACHE}"
                    popd
                    '''
                    writeFile file: 'ARM_IMAGE_NAME.azure.env', text: 'OpenLogic CentOS 7.3 latest'
                    writeFile file: 'ARM_OSVHD_NAME.azure.env', text: "SS-AUTOBUILT-OpenLogic-CentOS-7.3-latest-${BUILD_NAME}${BUILD_NUMBER}.vhd"
                    writeFile file: 'KERNEL_PACKAGE_NAME.azure.env', text: 'testKernel.rpm'
                }
                sh '''#!/bin/bash
                  echo ${BUILD_NUMBER}-$(crudini --get scripts/package_building/kernel_versions.ini KERNEL_BUILT folder) > ./build_name
                '''
                script {
                  currentBuild.displayName = readFile "./build_name"
                }
                stash includes: '*.azure.env', name: 'azure.env'
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/msft*/rpm/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
              post {
                success {
                  reportStageStatus("BuildSucceeded", 1)
                }
                failure {
                  reportStageStatus("BuildSucceeded", 0)
                }
              }
    }
    stage('publish_temp_artifacts') {
      when {
        beforeAgent true
        expression { params.ENABLED_STAGES.contains('publish_temp_artifacts') }
      }
      agent {
        node {
          label 'meta_slave'
        }
      }
      steps {
        dir("${env.KERNEL_ARTIFACTS_PATH}${env.BUILD_NUMBER}${env.BRANCH_NAME}") {
            unstash "${env.KERNEL_ARTIFACTS_PATH}"
            withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                               string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                               usernamePassword(credentialsId: 'smb_share_user_pass',
                                                passwordVariable: 'PASSWORD',
                                                usernameVariable: 'USERNAME')]) {
                sh '''#!/bin/bash
                    set -xe
                    bash "${WORKSPACE}/scripts/utils/publish_artifacts_to_smb.sh" \\
                        --build_number "${BUILD_NUMBER}-${BRANCH_NAME}" \\
                        --smb_url "${SMB_SHARE_URL}/temp-kernel-artifacts" --smb_username "${USERNAME}" \\
                        --smb_password "${PASSWORD}" --artifacts_path "${KERNEL_ARTIFACTS_PATH}" \\
                        --artifacts_folder_prefix "${FOLDER_PREFIX}"
                '''
            }
        }
      }
    }
    stage('boot_test') {
      when {
        beforeAgent true
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
          dir('kernel_version' + env.BUILD_NUMBER + env.BRANCH_NAME) {
            unstash 'kernel_version_ini'
            sh 'cat scripts/package_building/kernel_versions.ini'
          }
          sh '''#!/bin/bash
            OS_TYPE=${DISTRO_VERSION%_*}
            OS_TYPE=${OS_TYPE,,}
            bash scripts/azure_kernel_validation/validate_azure_vm_boot.sh \
                --build_name $BUILD_NAME --build_number "${BUILD_NUMBER}${BRANCH_NAME}" \
                --smb_share_username $USERNAME --smb_share_password $PASSWORD \
                --smb_share_url $SMB_SHARE_URL --vm_user_name $OS_TYPE \
                --os_type $OS_TYPE
            '''
        }
      }
      post {
        always {
          archiveArtifacts "${env.BUILD_NAME}${env.BUILD_NUMBER}${env.BRANCH_NAME}-boot-diagnostics/*.log"
        }
        failure {
          reportStageStatus("BootOnAzure", 0)
          sh 'echo "Load failure test results."'
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests-fail.xml')
        }
        success {
          reportStageStatus("BootOnAzure", 1)
          echo "Cleaning Azure resources up..."
          sh '''#!/bin/bash
            pushd ./scripts/azure_kernel_validation
            bash remove_azure_vm_resources.sh "${BUILD_NAME}${BUILD_NUMBER}${BRANCH_NAME}"
            popd
            '''
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests.xml')
        }
      }
    }
    stage('publish_artifacts') {
      when {
        beforeAgent true
        expression { params.ENABLED_STAGES.contains('publish_artifacts') }
      }
      agent {
        node {
          label 'meta_slave'
        }
      }
      steps {
        dir("${env.KERNEL_ARTIFACTS_PATH}${env.BUILD_NUMBER}${env.BRANCH_NAME}") {
            unstash "${env.KERNEL_ARTIFACTS_PATH}"
            withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                               string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                               usernamePassword(credentialsId: 'smb_share_user_pass', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')
                               ]) {
                sh '''#!/bin/bash
                    set -xe
                    bash "${WORKSPACE}/scripts/utils/publish_artifacts_to_smb.sh" \\
                        --build_number "${BUILD_NUMBER}-${BRANCH_NAME}" \\
                        --smb_url "${SMB_SHARE_URL}/${KERNEL_GIT_BRANCH_LABEL}-kernels" --smb_username "${USERNAME}" \\
                        --smb_password "${PASSWORD}" --artifacts_path "${KERNEL_ARTIFACTS_PATH}" \\
                        --artifacts_folder_prefix "${FOLDER_PREFIX}"
                '''
            }
        }
      }
    }
    stage('publish_vhd') {
      when {
        beforeAgent true
        expression { params.ENABLED_STAGES.contains('publish_vhd') }
      }
      parallel {
        stage('publish_azure_vhd') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('publish_azure_vhd') }
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
              build job: 'tool-turn-on-slaves', parameters: [string(name: 'RoleNameAndRGname', value: 'azure-slave-1@kernel_pipeline')], wait: false
              cleanWs()
              git env.AZURE_LINUX_AUTOMATION_REPO
              stash includes: '**' , name: 'azure-linux-automation'
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
              " -testLocation 'westus2'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'PUBLISH-VHD'" +
              " -OverrideVMSize 'Standard_D2_v2'" +
              " -ARMImageName '${ARM_IMAGE_NAME}'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ExitWithZero"
              )
              script {
                  env.ARM_OSVHD_NAME = readFile 'ARM_OSVHD_NAME.azure.env'
              }
              RunPowershellCommand(".\\Extras\\CopyVHDtoOtherStorageAccount.ps1" +
              " -sourceLocation westus2 " +
              " -destinationLocations 'westus,westus2,northeurope'" +
              " -destinationAccountType Standard" +
              " -sourceVHDName '${ARM_OSVHD_NAME}'" +
              " -destinationVHDName '${ARM_OSVHD_NAME}'"
              )
            }
          }
        }
        stage('publish_hyperv_vhd') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('publish_hyperv_vhd') }
            expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
          }
          agent {
            node {
              label 'hyper-v'
            }
          }
          steps {
            withCredentials(bindings: [string(credentialsId: 'LISA_IMAGES_SHARE_URL', variable: 'LISA_IMAGES_SHARE_URL'),
                                       string(credentialsId: 'LISA_TEST_DEPENDENCIES', variable: 'LISA_TEST_DEPENDENCIES'),
                                       string(credentialsId: 'VHD_UPLOAD_DESTINATION', variable: 'VHD_UPLOAD_DESTINATION')]) {
              println 'Running LISA...'
              unstash "${env.KERNEL_ARTIFACTS_PATH}"
              unstash "kernel_version_ini"
              PowerShellWrapper('''
                    & ".\\scripts\\lis_hyperv_platform\\main_perf.ps1"
                         -KernelVersionPath "scripts\\package_building\\kernel_versions.ini"
                         -LocalKernelFolder "scripts/package_building/${env:BUILD_NUMBER}-${env:BRANCH_NAME}-${env:KERNEL_ARTIFACTS_PATH}/**/deb"
                         -JobId "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}-msft"
                         -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}-f"
                         -VHDType "${env:DISTRO_VERSION}.ToLower().Split('_')[0]" -WorkingDirectory "C:\\workspace"
                         -OSVersion "${env:DISTRO_VERSION}.Split('_')[1]"
                         -LISAImagesShareUrl "${env:LISA_IMAGES_SHARE_URL}" -XmlTest "None"
                         -LisaTestDependencies "${env:LISA_TEST_DEPENDENCIES}"
                         -VHDDestination ${env:VHD_UPLOAD_DESTINATION}
                      ''')
              println 'Finished running LISA.'
            }
          }
        }
      }
    }
    stage('validation') {
     when {
      beforeAgent true
      expression { params.ENABLED_STAGES.contains('validation') }
     }
     parallel {
      stage('validation_functional_hyperv') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_functional_hyperv') }
          }
          agent {
            node {
              label 'hyper-v'
            }
          }
          steps {
            withCredentials(bindings: [string(credentialsId: 'LISA_IMAGES_SHARE_URL', variable: 'LISA_IMAGES_SHARE_URL'),
                                       string(credentialsId: 'AZURE_SAS', variable: 'AZURE_SAS'),
                                       string(credentialsId: 'AZURE_STORAGE_URL', variable: 'AZURE_STORAGE_URL'),
                                       string(credentialsId: 'LISA_TEST_DEPENDENCIES', variable: 'LISA_TEST_DEPENDENCIES'),
                                       string(credentialsId: 'DB_CONFIG_KERNEL', variable: 'DB_CONFIG_KERNEL'),
                                       string(credentialsId: 'LISA_KERNEL_LOG_DESTINATION', variable: 'LISA_KERNEL_LOG_DESTINATION'),
                                       file(credentialsId: 'KERNEL_QUALITY_REPORTING_DB_CONFIG',
                                            variable: 'DBConfigPath')]) {
                echo 'Running LISA...'
                dir('kernel_version' + env.BUILD_NUMBER + env.BRANCH_NAME) {
                    unstash 'kernel_version_ini'
                    PowerShellWrapper('cat scripts/package_building/kernel_versions.ini')
                }
                PowerShellWrapper('''
                    & ".\\scripts\\lis_hyperv_platform\\main.ps1"
                        -KernelVersionPath "kernel_version${env:BUILD_NUMBER}${env:BRANCH_NAME}\\scripts\\package_building\\kernel_versions.ini"
                        -JobId "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}"
                        -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}"
                        -VHDType "${env:DISTRO_VERSION}.ToLower().Split('_')[0]" -WorkingDirectory "C:\\workspace"
                        -OSVersion "${env:DISTRO_VERSION}.Split('_')[1]" -LISAManageVMS:$true
                        -LISAImagesShareUrl "${env:LISA_IMAGES_SHARE_URL}" -XmlTest "${env:LISA_TEST_XML}"
                        -AzureToken "${env:AZURE_SAS}"
                        -AzureUrl "${env:AZURE_STORAGE_URL}${env:KERNEL_GIT_BRANCH_LABEL}-kernels"
                        -LisaTestDependencies "${env:LISA_TEST_DEPENDENCIES}"
                        -PipelineName "pipeline-msft-kernel-validation/${env:BRANCH_NAME}"
                        -DBConfigPath "${env:DBConfigPath}"
                        -LisaLogDBConfigPath "${env:DB_CONFIG_KERNEL}"
                        -LogsPath "${env:LISA_KERNEL_LOG_DESTINATION}"
                  ''')
                echo 'Finished running LISA.'
              }
            }
          post {
            always {
              archiveArtifacts "${BUILD_NAME}${BUILD_NUMBER}${BRANCH_NAME}\\TestResults\\**\\*"
              junit "${BUILD_NAME}${BUILD_NUMBER}${BRANCH_NAME}\\TestResults\\**\\*.xml"
            }
            success {
              echo 'Cleaning up LISA environment...'
              PowerShellWrapper('''
                  & ".\\scripts\\lis_hyperv_platform\\tear_down_env.ps1" -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}"
                ''')
            }
          }
        }
        stage('validation_functional_jessie_hyperv') {
          when {
            beforeAgent true
            expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
            expression { params.ENABLED_STAGES.contains('validation_functional_jessie_hyperv') }
          }
          agent {
            node {
              label 'hyper-v'
            }
          }
          steps {
            withCredentials(bindings: [string(credentialsId: 'LISA_IMAGES_SHARE_URL', variable: 'LISA_IMAGES_SHARE_URL'),
                                       string(credentialsId: 'AZURE_SAS', variable: 'AZURE_SAS'),
                                       string(credentialsId: 'AZURE_STORAGE_URL', variable: 'AZURE_STORAGE_URL'),
                                       string(credentialsId: 'LISA_TEST_DEPENDENCIES', variable: 'LISA_TEST_DEPENDENCIES'),
                                       string(credentialsId: 'DB_CONFIG_KERNEL', variable: 'DB_CONFIG_KERNEL'),
                                       string(credentialsId: 'LISA_KERNEL_LOG_DESTINATION', variable: 'LISA_KERNEL_LOG_DESTINATION'),
                                       file(credentialsId: 'KERNEL_QUALITY_REPORTING_DB_CONFIG',
                                            variable: 'DBConfigPath')]) {
                echo 'Running LISA for Debian Jessie...'
                dir('kernel_version' + env.BUILD_NUMBER + env.BRANCH_NAME) {
                    unstash 'kernel_version_ini'
                    PowerShellWrapper('cat scripts/package_building/kernel_versions.ini')
                }
                PowerShellWrapper('''
                    & ".\\scripts\\lis_hyperv_platform\\main.ps1"
                        -KernelVersionPath "kernel_version${env:BUILD_NUMBER}${env:BRANCH_NAME}\\scripts\\package_building\\kernel_versions.ini"
                        -JobId "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}jessie"
                        -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}jessie"
                        -VHDType "Debian" -OSVersion "8.11" -WorkingDirectory "C:\\workspace"
                        -LISAImagesShareUrl "${env:LISA_IMAGES_SHARE_URL}" -XmlTest "${env:LISA_TEST_XML}"
                        -AzureToken "${env:AZURE_SAS}" -AzureUrl "${env:AZURE_STORAGE_URL}${env:KERNEL_GIT_BRANCH_LABEL}-kernels"
                        -LisaTestDependencies "${env:LISA_TEST_DEPENDENCIES}"
                        -PipelineName "pipeline-msft-kernel-validation/${env:BRANCH_NAME}"
                        -DBConfigPath "${env:DBConfigPath}"
                        -LisaLogDBConfigPath "${env:DB_CONFIG_KERNEL}"
                        -LogsPath "${env:LISA_KERNEL_LOG_DESTINATION}"
                  ''')
                echo 'Finished running LISA for Debian Jessie.'
              }
            }
          post {
            always {
              archiveArtifacts "${BUILD_NAME}${BUILD_NUMBER}${BRANCH_NAME}jessie\\TestResults\\**\\*"
              junit "${BUILD_NAME}${BUILD_NUMBER}${BRANCH_NAME}jessie\\TestResults\\**\\*.xml"
            }
            success {
              echo 'Cleaning up LISA environment...'
              PowerShellWrapper('''
                  & ".\\scripts\\lis_hyperv_platform\\tear_down_env.ps1" -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}${env:BRANCH_NAME}jessie"
                ''')
            }
          }
        }
        stage('validation_functional_azure') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_functional_azure') }
          }
          agent {
            node {
              label 'azure'
            }
          }
          steps {
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
              build job: 'tool-turn-on-slaves', parameters: [string(name: 'RoleNameAndRGname', value: 'azure-slave-1@kernel_pipeline')], wait: false
              cleanWs()
              unstash 'azure-linux-automation'
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
              " -testLocation 'westus2'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'BVTMK'" +
              " -OverrideVMSize 'Standard_D1_v2'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ExitWithZero"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -testLocation 'westus'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'DEPLOYMENT-LIMITED'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ExitWithZero"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -testLocation 'westus'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testCycle 'DEPLOYMENT-LIMITED'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -StorageAccount 'ExistingStorage_Premium'" +
              " -ExitWithZero"
              )
              junit "report\\*-junit.xml"
              RunPowershellCommand(".\\Extras\\AnalyseAllResults.ps1")
            }
          }
        }
        stage('validation_perf_azure_net') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_perf_azure') }
          }
          agent {
            node {
              label 'azure'
            }
          }
          steps {
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
              build job: 'tool-turn-on-slaves', parameters: [string(name: 'RoleNameAndRGname', value: 'azure-slave-1@kernel_pipeline')], wait: false
              cleanWs()
              unstash 'azure-linux-automation'
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
              " -EnableAcceleratedNetworking" +
              " -ExitWithZero"
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
              " -EnableAcceleratedNetworking" +
              " -ExitWithZero"
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
              " -EnableAcceleratedNetworking" +
              " -ExitWithZero"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-UDPLOSS'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_UDP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'PERF-UDPLOSS'" +
              " -EnableAcceleratedNetworking" +
              " -ExitWithZero"
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
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ExitWithZero"
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
              " -ExitWithZero"
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
              " -ExitWithZero"
              )
              RunPowershellCommand(".\\RunAzureTests.ps1" +
              " -ArchiveLogDirectory 'Z:\\Logs_Azure'" +
              " -OsVHD '${ARM_OSVHD_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -testLocation 'westus2'" +
              " -testCycle 'PERF-UDPLOSS'" +
              " -OverrideVMSize 'Standard_D15_v2'" +
              " -StorageAccount 'ExistingStorage_Standard'" +
              " -ResultDBTable 'Perf_Network_UDP_Azure_MsftKernel'" +
              " -ResultDBTestTag 'PERF-UDPLOSS'" +
              " -ExitWithZero"
              )
              junit "report\\*-junit.xml"
              RunPowershellCommand(".\\Extras\\AnalyseAllResults.ps1")
            }
          }
        }
        stage('validation_perf_azure_stor') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_perf_azure') }
          }
          agent {
            node {
              label 'azure'
            }
          }
          steps {
            withCredentials([file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
              build job: 'tool-turn-on-slaves', parameters: [string(name: 'RoleNameAndRGname', value: 'azure-slave-1@kernel_pipeline')], wait: false
              cleanWs()
              unstash 'azure-linux-automation'
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
              " -customKernel 'localfile:${KERNEL_PACKAGE_NAME}'" +
              " -DistroIdentifier '${BUILD_NAME}${BUILD_NUMBER}'" +
              " -ARMImageName '${ARM_IMAGE_NAME}'" +
              " -testLocation 'centralus'" +
              " -testCycle 'PERF-FIO'" +
              " -OverrideVMSize 'Standard_DS14_v2'" +
              " -ResultDBTable 'Perf_Storage_Azure_MsftKernel'" +
              " -ResultDBTestTag 'FIO-12DISKS'" +
              " -StorageAccount 'NewStorage_Premium'" +
              " -ExitWithZero"
              )
              junit "report\\*-junit.xml"
              RunPowershellCommand(".\\Extras\\AnalyseAllResults.ps1")
            }
          }
        }
        stage('validation_perf_hyperv') {
          when {
            beforeAgent true
            expression { params.DISTRO_VERSION.toLowerCase().contains('centos') }
            expression { params.ENABLED_STAGES.contains('validation_perf_hyperv') }
          }
          agent {
            node {
              label 'jenkins-meta-slave'
            }
          }
          steps {
              dir('kernel_version' + env.BUILD_NUMBER + env.BRANCH_NAME) {
                unstash 'kernel_version_ini'
              }
              script {
                    iniPath = "${env:WORKSPACE}/kernel_version${env:BUILD_NUMBER}${env:BRANCH_NAME}/scripts/package_building/kernel_versions.ini"
                    kernelPath = sh (script: "crudini --get ${iniPath} KERNEL_BUILT folder", returnStdout: true)
                    build job: "performance-jobs/Pipeline_Performance", parameters: [
                        string(name: 'KERNEL', value: "${kernelPath}")], wait: false;
              }
              echo "Triggered Local Hyper-V Performance tests."
            
          }
        }
      }
    }
  }
}
