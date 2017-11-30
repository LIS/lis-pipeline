def PowerShellWrapper(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"\$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
}

pipeline {
  agent {
    node {
      label 'master'
    }
  }
  stages {
          stage('Build Kernel Ubuntu') {
              when { environment name: 'OS_TYPE', value: 'ubuntu' }
              agent {
                node {
                  label 'ubuntu_kernel_builder'
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
                }
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
          }
          stage('Build Kernel Centos') {
              when { environment name: 'OS_TYPE', value: 'centos' }
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
                    exit 0
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
                }
                stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
                archiveArtifacts 'scripts/package_building/kernel_versions.ini'
              }
    }
    stage('Test Kernel') {
      agent {
        node {
          label 'ubuntu_kernel_builder'
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
          sh '''#!/bin/bash
            set -xe
            exit 0
            KERNEL_VERSION_FILE="./kernel_version${BUILD_NUMBER}/scripts/package_building/kernel_versions.ini"
            KERNEL_FOLDER=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT folder)
            DESIRED_KERNEL_VERSION=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT version)
            DESIRED_KERNEL_TAG=$(crudini --get $KERNEL_VERSION_FILE KERNEL_BUILT git_tag)
            pushd ./scripts/azure_kernel_validation
            bash create_azure_vm.sh --build_number "$BUILD_NAME$BUILD_NUMBER" --clone_repo y \
                                    --vm_params "username=$USERNAME,password=$PASSWORD,samba_path=$SMB_SHARE_URL/$KERNEL_GIT_BRANCH-kernels,kernel_path=$KERNEL_FOLDER" \
                                    --deploy_data azure_kernel_validation --resource_group kernel-validation \
                                    --os_type $OS_TYPE
            popd

            . ./scripts/package_building/utils.sh
            INTERVAL=5
            COUNTER=0
            while [ $COUNTER -lt $AZURE_MAX_RETRIES ]; do
                public_ip_raw=$(az network public-ip show --name "$BUILD_NAME$BUILD_NUMBER-PublicIP" --resource-group kernel-validation --query \'{address: ipAddress }\')
                public_ip=`echo $public_ip_raw | awk \'{if (NR == 1) {print $3}}\' | tr -d \'"\'`
                if [ !  -z $public_ip ]; then
                    echo "Public ip available: $public_ip."
                    break
                else
                    echo "Public ip not available."
                fi
                let COUNTER=COUNTER+1

                if [ -n "$INTERVAL" ]; then
                    sleep $INTERVAL
                fi
            done
            if [ $COUNTER -eq $AZURE_MAX_RETRIES ]; then
                echo "Failed to get public ip. Exiting..."
                exit 2
            fi

            INTERVAL=5
            COUNTER=0
            while [ $COUNTER -lt $AZURE_MAX_RETRIES ]; do
                KERNEL_NAME=`ssh -i ~/azure_priv_key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$public_ip uname -r || true`
                echo $KERNEL_NAME
                if [ $KERNEL_NAME == *"$DESIRED_KERNEL_TAG"* ]; then
                    echo "Kernel matched."
                    exit 0
                else
                    echo "Kernel $KERNEL_NAME does not match with desired Kernel tag: $DESIRED_KERNEL_TAG"
                fi
                let COUNTER=COUNTER+1

                if [ -n "$INTERVAL" ]; then
                    sleep $INTERVAL
                fi
            done

            exit 1
            '''
        }
        
      }
      post {
        always {
          echo "Cleaning Azure resources up..."
          sh '''#!/bin/bash
            exit 0
            pushd ./scripts/azure_kernel_validation
            bash remove_azure_vm_resources.sh "$BUILD_NAME$BUILD_NUMBER"
            popd
            '''
        }
        
        failure {
          sh 'echo "Load failure test results."'
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests-fail.xml')
        }
        
        success {
          nunit(testResultsPattern: 'scripts/azure_kernel_validation/tests.xml')
          withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                           string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                           usernamePassword(credentialsId: 'smb_share_user_pass', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')
                           ]) {
            sh '''#!/bin/bash
                set -xe
                MOUNT_POINT="/tmp/${BUILD_NUMBER}"
                mkdir -p $MOUNT_POINT
                sudo mount -t cifs "${SMB_SHARE_URL}/${KERNEL_GIT_BRANCH}-kernels" $MOUNT_POINT \
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
    stage ('Publish artifacts') {
      agent {
        node {
          label 'ubuntu_kernel_builder'
        }
      }
      steps {
          echo 'Publish artifacts to SMB share.'
      }
    }

    stage('LISA') {
      agent {
        node {
          label 'lis-f2334'
        }
        
      }
      steps {
        withCredentials(bindings: [string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                                   string(credentialsId: 'WIN_SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                                   usernamePassword(credentialsId: 'smb_share_user_pass', passwordVariable: 'PASSWORD', usernameVariable: 'USERNAME')
                                 ]) {
            echo 'Running LISA...'
            dir('kernel_version' + env.BUILD_NUMBER) {
                unstash 'kernel_version_ini'
                PowerShellWrapper('cat scripts/package_building/kernel_versions.ini')
            }
            PowerShellWrapper('& ".\\scripts\\lis_hyperv_platform\\main.ps1" -KernelVersionPath "kernel_version${env:BUILD_NUMBER}\\scripts\\package_building\\kernel_versions.ini" -SharedStoragePath $env:SMB_SHARE_URL -ShareUser $env:USERNAME -SharePassword $env:PASSWORD -JobId "${env:BUILD_NAME}${env:BUILD_NUMBER}" -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}" -XmlTest KvpTests.xml -VHDType $env:OS_TYPE -WorkingDirectory "C:\\workspace" -IdRSAPub "C:\\bin\\id_rsa.pub"')
            echo 'Finished running LISA.'
          }
        }
      post {
        always {
          archiveArtifacts 'lis-test\\WS2012R2\\lisa\\TestResults\\KvpTests*\\*.log'
          archiveArtifacts 'lis-test\\WS2012R2\\lisa\\TestResults\\KvpTests*\\*.xml'
          junit 'lis-test\\WS2012R2\\lisa\\TestResults\\KvpTests*\\Report-*.xml'
        }
        success {
          echo 'Cleaning up LISA environment...'
          PowerShellWrapper('& ".\\scripts\\lis_hyperv_platform\\tear_down_env.ps1" -InstanceName "${env:BUILD_NAME}${env:BUILD_NUMBER}"')
        }
      }
    }
  }
  environment {
    KERNEL_GIT_BRANCH = 'unstable'
    KERNEL_ARTIFACTS_PATH = 'kernel-artifacts'
    THREAD_NUMBER = 'x2'
    UBUNTU_VERSION = '16'
    BUILD_PATH = '/mnt/tmp/kernel-build-folder'
    KERNEL_CONFIG = './Microsoft/config-azure'
    CLEAN_ENV = 'False'
    USE_CCACHE = 'True'
    AZURE_MAX_RETRIES = '40'
    BUILD_NAME = 'kernell'
    OS_TYPE = 'ubuntu'
  }
}
