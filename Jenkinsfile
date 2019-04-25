#!/usr/bin/env groovy

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

def getVhdLocation(basePath, distroVersion) {
    def distroFamily = distroVersion.split('_')[0]
    return "${basePath}\\" + distroFamily + "\\" + distroVersion + "\\" + distroVersion + ".vhdx"
}

def prepareEnv(branch, remote, distroVersion, functionalTests, platform) {
    cleanWs()
    git branch: branch, url: remote
    script {
      env.AZURE_OS_IMAGE = env.AZURE_UBUNTU_IMAGE_BIONIC
      env.PACKAGE_TYPE = "deb"
      if (distroVersion.toLowerCase().contains("centos")) {
        env.AZURE_OS_IMAGE = env.AZURE_CENTOS_7_IMAGE
        env.PACKAGE_TYPE = "rpm"
      }
      if (functionalTests.contains('ALL')) {
          env.LISAV2_PARAMS = "-TestCategory 'Functional'"
      }
      if (functionalTests.contains('BVT')) {
          env.LISAV2_PARAMS = "-TestCategory 'BVT'"
      }
      if (functionalTests.contains('FVT')) {
          if (platform == "Azure") {
              env.LISAV2_PARAMS = "-TestCategory 'Functional,Community,Stress,BVT' -TestArea 'KVP,SRIOV,NETWORK,STORAGE,WALA,CORE,KDUMP,LTP,STRESS,BVT,NVME'"
              LISAV2_AZURE_REGION = "eastus2"
          } else if (platform == "HyperV") {
              env.LISAV2_PARAMS = "-TestCategory 'Functional' -TestArea 'KVP,FCOPY,CORE,LIS,NETWORK,KDUMP,STORAGE,PROD_CHECKPOINT,DYNAMIC_MEMORY,RUNTIME_MEMORY,BACKUP'"
          }
      }
    }
}

def unstashKernel(kernelStash) {
    unstash kernelStash
    powershell """
        \$rmPath = "\${env:ProgramFiles}\\Git\\usr\\bin\\rm.exe"
        \$basePath = "./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${kernelStash}/*/${env.PACKAGE_TYPE}"

        & \$rmPath -rf "\${basePath}/*dbg*"
        & \$rmPath -rf "\${basePath}/*devel*"
        & \$rmPath -rf "\${basePath}/*debug*"
    """
}


pipeline {
  parameters {
    string(defaultValue: "stable", description: 'Branch to be built', name: 'KERNEL_GIT_BRANCH')
    string(defaultValue: "stable", description: 'Branch label (stable or unstable)', name: 'KERNEL_GIT_BRANCH_LABEL')
    choice(choices: 'Ubuntu_18.04.1\nCentOS_7.5', description: 'Distro version.', name: 'DISTRO_VERSION')
    choice(choices: 'False\nTrue', description: 'Enable kernel debug', name: 'KERNEL_DEBUG')
    choice(choices: 'BVT\nFVT\nALL', description: 'Functional Tests', name: 'FUNCTIONAL_TESTS')
    string(defaultValue: "build_artifacts, publish_temp_artifacts, boot_test, publish_artifacts, publish_vhd, publish_azure_vhd, publish_hyperv_vhd, validation_functional_hyperv, validation_functional_jessie_hyperv, validation_functional_azure, validation_perf_azure, validation_perf_hyperv",
           description: 'What stages to run', name: 'ENABLED_STAGES')
  }
  environment {
    LISAV2_REMOTE = "https://github.com/lis/LISAv2.git"
    LISAV2_BRANCH = "master"
    LISAV2_AZURE_REGION = "westus2"
    LISAV2_RG_IDENTIFIER = "msftk"
    LISAV2_AZURE_VM_SIZE_SMALL = "Standard_A2"
    LISAV2_AZURE_VM_SIZE_LARGE = "Standard_E64_v3"
    KERNEL_ARTIFACTS_PATH = 'kernel-artifacts'
    BUILD_PATH = '/mnt/tmp/kernel-build-folder'
    KERNEL_CONFIG = 'Microsoft/config-azure'
    CLEAN_ENV = 'True'
    USE_CCACHE = 'True'
    BUILD_NAME = 'm'
    FOLDER_PREFIX = 'msft'
    AZURE_UBUNTU_IMAGE_BIONIC = "Canonical UbuntuServer 18.04-DAILY-LTS latest"
    AZURE_CENTOS_7_IMAGE = "OpenLogic CentOS 7.5 latest"
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
                        --thread_number "x3" \\
                        --debian_os_version "16" \\
                        --build_path "${BUILD_PATH}" \\
                        --kernel_config "${KERNEL_CONFIG}" \\
                        --clean_env "${CLEAN_ENV}" \\
                        --use_ccache "${USE_CCACHE}" \\
                        --enable_kernel_debug "${KERNEL_DEBUG}"
                    popd
                '''
              }

              sh '''#!/bin/bash
                  echo ${BUILD_NUMBER}-$(crudini --get scripts/package_building/kernel_versions.ini KERNEL_BUILT folder) > ./build_name
                '''
                script {
                  currentBuild.displayName = readFile "./build_name"
                }
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/**/deb/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
              post {
                failure {
                  reportStageStatus("BuildSucceeded", 0)
                }
                success {
                  reportStageStatus("BuildSucceeded", 1)
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
                        --thread_number "x3" \\
                        --build_path "${BUILD_PATH}" \\
                        --kernel_config "${KERNEL_CONFIG}" \\
                        --clean_env "${CLEAN_ENV}" \\
                        --use_ccache "${USE_CCACHE}" \\
                        --enable_kernel_debug "${KERNEL_DEBUG}"
                    popd
                '''
                }
                sh '''#!/bin/bash
                  echo ${BUILD_NUMBER}-$(crudini --get scripts/package_building/kernel_versions.ini KERNEL_BUILT folder) > ./build_name
                '''
                script {
                  currentBuild.displayName = readFile "./build_name"
                }
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/**/rpm/**"),
                      name: "${env.KERNEL_ARTIFACTS_PATH}"
                sh '''
                    set -xe
                    rm -rf "scripts/package_building/${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}"
                '''
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
              post {
                failure {
                  reportStageStatus("BuildSucceeded", 0)
                }
                success {
                  reportStageStatus("BuildSucceeded", 1)
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
            withCredentials([string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
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
      post {
        failure {
          reportStageStatus("BootOnAzure", 0)
        }
        success {
          reportStageStatus("BootOnAzure", 1)
        }
      }
      parallel {
        stage('boot_test_large') {
            when {
              beforeAgent true
              expression { params.ENABLED_STAGES.contains('boot_test_large') }
            }
            agent {
              node {
                label 'azure'
              }
            }
            steps {
                withCredentials(bindings: [
                  file(credentialsId: 'Azure_Secrets_TESTONLY_File',
                       variable: 'Azure_Secrets_File')
                ]) {
                    prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "Azure")
                    unstashKernel(env.KERNEL_ARTIFACTS_PATH)
                    RunPowershellCommand(".\\Run-LisaV2.ps1" +
                        " -TestLocation '${LISAV2_AZURE_REGION}'" +
                        " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                        " -TestPlatform 'Azure'" +
                        " -CustomKernel 'localfile:./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/*/${env.PACKAGE_TYPE}/*.${env.PACKAGE_TYPE}'" +
                        " -OverrideVMSize '${env.LISAV2_AZURE_VM_SIZE_LARGE}'" +
                        " -ARMImageName '${env.AZURE_OS_IMAGE}'" +
                        " -TestNames 'VERIFY-LIS-MODULES-VERSION'" +
                        " -StorageAccount 'ExistingStorage_Standard'" +
                        " -XMLSecretFile '${env.Azure_Secrets_File}'" +
                        " -CustomParameters 'DiskType = Managed'"
                    )
                }
            }
            post {
              always {
                junit "Report\\*-junit.xml"
                archiveArtifacts "TestResults\\**\\*"
              }
            }
        }
        stage('boot_test_small') {
            agent {
              node {
                label 'azure'
              }
            }
            steps {
                withCredentials(bindings: [
                  file(credentialsId: 'Azure_Secrets_TESTONLY_File',
                       variable: 'Azure_Secrets_File')
                ]) {
                    prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "Azure")
                    unstashKernel(env.KERNEL_ARTIFACTS_PATH)
                    RunPowershellCommand(".\\Run-LisaV2.ps1" +
                        " -TestLocation '${LISAV2_AZURE_REGION}'" +
                        " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                        " -TestPlatform 'Azure'" +
                        " -CustomKernel 'localfile:./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/*/${env.PACKAGE_TYPE}/*.${env.PACKAGE_TYPE}'" +
                        " -OverrideVMSize '${env.LISAV2_AZURE_VM_SIZE_SMALL}'" +
                        " -ARMImageName '${env.AZURE_OS_IMAGE}'" +
                        " -TestNames 'VERIFY-LIS-MODULES-VERSION'" +
                        " -StorageAccount 'ExistingStorage_Standard'" +
                        " -XMLSecretFile '${env.Azure_Secrets_File}'" +
                        " -CustomParameters 'DiskType = Managed'"
                    )
                }
            }
            post {
              always {
                junit "Report\\*-junit.xml"
                archiveArtifacts "TestResults\\**\\*"
              }
            }
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
            withCredentials([string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
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
    stage('publish_azure_vhd') {
      when {
        beforeAgent true
        expression { params.ENABLED_STAGES.contains('publish_azure_vhd') }
      }
      agent {
        node {
          label 'azure'
        }
      }
      steps {
        withCredentials(bindings: [
          file(credentialsId: 'Azure_Secrets_TESTONLY_File',
               variable: 'Azure_Secrets_File')
        ]) {
            prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "Azure")
            unstashKernel(env.KERNEL_ARTIFACTS_PATH)
            RunPowershellCommand(".\\Run-LisaV2.ps1" +
                " -TestLocation '${LISAV2_AZURE_REGION}'" +
                " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                " -TestPlatform 'Azure'" +
                " -CustomKernel 'localfile:./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/*/${env.PACKAGE_TYPE}/*.${env.PACKAGE_TYPE}'" +
                " -OverrideVMSize '${env.LISAV2_AZURE_VM_SIZE_SMALL}'" +
                " -ARMImageName '${env.AZURE_OS_IMAGE}'" +
                " -TestNames 'CAPTURE-VHD-BEFORE-TEST'" +
                " -XMLSecretFile '${env.Azure_Secrets_File}'"
            )
            script {
                env.CapturedVHD = readFile 'CapturedVHD.azure.env'
            }
            stash includes: 'CapturedVHD.azure.env', name: 'CapturedVHD.azure.env'
            println("Captured VHD : ${env.CapturedVHD}")
        }
      }
      post {
        always {
          junit "Report\\*-junit.xml"
          archiveArtifacts "TestResults\\**\\*"
        }
      }
    }

    stage('validation') {
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
            withCredentials(bindings: [
              file(credentialsId: 'HyperV_Secrets_File',
                   variable: 'HyperV_Secrets_File'),
              string(credentialsId: 'LISAV2_IMAGES_SHARE_URL',
                   variable: 'LISAV2_IMAGES_SHARE_URL')
            ]) {
                prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "HyperV")
                unstashKernel(env.KERNEL_ARTIFACTS_PATH)
                script {
                  env.HYPERV_VHD_PATH = getVhdLocation(LISAV2_IMAGES_SHARE_URL, DISTRO_VERSION)
                }
                println("Current VHD: ${env.HYPERV_VHD_PATH}")
                RunPowershellCommand(".\\Run-LisaV2.ps1" +
                    " -TestLocation 'localhost'" +
                    " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                    " -TestPlatform 'HyperV'" +
                    " ${env.LISAV2_PARAMS}" +
                    " -OsVHD '${env.HYPERV_VHD_PATH}'" +
                    " -CustomKernel 'localfile:./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/*/${env.PACKAGE_TYPE}/*.${env.PACKAGE_TYPE}'" +
                    " -XMLSecretFile '${env.HyperV_Secrets_File}'"
                )
            }
          }
          post {
            always {
              junit "Report\\*-junit.xml"
              archiveArtifacts "TestResults\\**\\*"
            }
          }
        }

        stage('validation_functional_jessie_hyperv') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_functional_jessie_hyperv') }
            expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
          }
          agent {
            node {
              label 'hyper-v'
            }
          }
          steps {
            withCredentials(bindings: [
              file(credentialsId: 'HyperV_Secrets_File',
                   variable: 'HyperV_Secrets_File'),
              string(credentialsId: 'LISAV2_IMAGES_SHARE_URL',
                   variable: 'LISAV2_IMAGES_SHARE_URL')
            ]) {
                prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "HyperV")
                unstashKernel(env.KERNEL_ARTIFACTS_PATH)
                script {
                  env.HYPERV_VHD_PATH = getVhdLocation(LISAV2_IMAGES_SHARE_URL, "Debian_8.11")
                }
                println("Current VHD: ${env.HYPERV_VHD_PATH}")
                RunPowershellCommand(".\\Run-LisaV2.ps1" +
                    " -TestLocation 'localhost'" +
                    " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                    " -TestPlatform 'HyperV'" +
                    " ${env.LISAV2_PARAMS}" +
                    " -OsVHD '${env.HYPERV_VHD_PATH}'" +
                    " -CustomKernel 'localfile:./scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/*/${env.PACKAGE_TYPE}/*.${env.PACKAGE_TYPE}'" +
                    " -XMLSecretFile '${env.HyperV_Secrets_File}'"
                )
            }
          }
          post {
            always {
              junit "Report\\*-junit.xml"
              archiveArtifacts "TestResults\\**\\*"
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
            withCredentials(bindings: [
              file(credentialsId: 'Azure_Secrets_TESTONLY_File',
                   variable: 'Azure_Secrets_File')
            ]) {
                prepareEnv(LISAV2_BRANCH, LISAV2_REMOTE, DISTRO_VERSION, FUNCTIONAL_TESTS, "Azure")
                unstash 'CapturedVHD.azure.env'
                script {
                    env.CapturedVHD = readFile 'CapturedVHD.azure.env'
                }
                println("VHD under test : ${env.CapturedVHD}")
                RunPowershellCommand(".\\Run-LisaV2.ps1" +
                    " -TestLocation '${LISAV2_AZURE_REGION}'" +
                    " -RGIdentifier '${env.LISAV2_RG_IDENTIFIER}'" +
                    " -TestPlatform 'Azure'" +
                    " ${env.LISAV2_PARAMS} " +
                    " -OsVHD '${env.CapturedVHD}'" +
                    " -XMLSecretFile '${env.Azure_Secrets_File}'"
                )
            }
          }
          post {
            always {
              junit "Report\\*-junit.xml"
              archiveArtifacts "TestResults\\**\\*"
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
            println("TBD")
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
            println("TBD")
          }
        }

        stage('validation_perf_hyperv') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_perf_hyperv') }
            expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
          }
          agent {
            node {
              label "net_perf"
            }
          }
          steps {
            println("TBD")
          }
        }

        stage('validation_sriov_hyperv') {
          when {
            beforeAgent true
            expression { params.ENABLED_STAGES.contains('validation_sriov_hyperv') }
            expression { params.DISTRO_VERSION.toLowerCase().contains('ubuntu') }
          }
          agent {
            node {
              label 'sriov_mlnx'
            }
          }
          steps {
            println("TBD")
          }
        }
      }
    }
  }
}
