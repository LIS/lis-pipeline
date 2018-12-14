# How to skip kernel build stage

It is very cumbersome to build kernels everytime you need to test a pipeline change that does not affect the build process.

Every stage after the build one is conditioned not by the execution of the build, but by the existence of a stashed kernel_versions.ini file.


To skip the build stage successfully, you require:

- kernel version
- kernel git tag
- kernel folder

Example kernel_version.ini: 

```ini
[KERNEL_BUILT]
version = 4.18.0-rc1
git_tag = 8439c34
folder = linux-next-4.18.0-8439c34-21062018
```
### Jenkins stage to stash kernel versions

```groovy
stage('fake_build') {
  agent {
    node {
      label 'meta_slave'
    }
  }
  steps {
    sh '''#!/bin/bash
      KERNEL_VERSION="4.18.0-rc1"
      KERNEL_GIT_TAG="8439c34"
      KERNEL_FOLDER="linux-next-4.18.0-8439c34-21062018"

      ini_file="kernel_version.ini"
      ini_folder="scripts/package_building/"
      ini_file_path="${ini_folder}/${ini_file}"
      mkdir -p $ini_folder
      touch $ini_file_path

      crudini --set $ini_file_path KERNEL_BUILT version $KERNEL_VERSION
      crudini --set $ini_file_path KERNEL_BUILT git_tag $KERNEL_GIT_TAG
      crudini --set $ini_file_path KERNEL_BUILT folder $KERNEL_FOLDER

      echo "${BUILD_NUMBER}-${KERNEL_FOLDER}" > ./build_name
    '''
    script {
      currentBuild.displayName = readFile "./build_name"
    }
    stash includes: 'scripts/package_building/kernel_versions.ini', name: 'kernel_version_ini'
  }
}
```

### Jenkins stage for stashing artifacts already on an SMB share

```groovy
stage('stash_kernel_artifacts') {
  agent {
    node {
      label 'meta_slave'
    }
  }
  steps {
    withCredentials([string(credentialsId: 'KERNEL_GIT_URL', variable: 'KERNEL_GIT_URL'),
                   string(credentialsId: 'SMB_SHARE_URL', variable: 'SMB_SHARE_URL'),
                   usernamePassword(credentialsId: 'smb_share_user_pass',
                                    passwordVariable: 'PASSWORD',
                                    usernameVariable: 'USERNAME')]) {
      sh '''#!/bin/bash
        LOCAL_ARTIFACTS_FOLDER="scripts/package_building/${BUILD_NUMBER}-${BRANCH_NAME}-${KERNEL_ARTIFACTS_PATH}"

        MOUNT_POINT="/tmp/${BUILD_NUMBER}"
        mkdir -p $MOUNT_POINT
        sudo mount -t cifs "${SMB_SHARE_URL}" $MOUNT_POINT \
          -o vers=3.0,username=${USERNAME},password=${PASSWORD},dir_mode=0777,file_mode=0777,sec=ntlmssp

        ls -laith "${MOUNT_POINT}"
        ls -liath "${MOUNT_POINT}/${FOLDER_PREFIX}-${BUILD_NUMBER}-${BRANCH_NAME}" || true

        #sudo cp -rf "${MOUNT_POINT}/${FOLDER_PREFIX}-${BUILD_NUMBER}-${BRANCH_NAME}" "${LOCAL_ARTIFACTS_FOLDER}/"
        sudo umount $MOUNT_POINT
      '''
      stash includes: ("scripts/package_building/${env.BUILD_NUMBER}-${env.BRANCH_NAME}-${env.KERNEL_ARTIFACTS_PATH}/"),
                       name: "${env.KERNEL_ARTIFACTS_PATH}"
    }
  }
}
```
