# Jenkins Blue Ocean pipeline for kernel testing

## Jenkins

### Requirements

* Jenkins with blue ocean installed (version for jenkins and blue ocean plugin, jvm version, and how to install)
* Git repo with the Jenkinsfile definition (token with read/write access required, the default path for the Jenkinsfile) .
* Linux slaves (supported versions, how to connect them)
* Windows slaves (supported versions, how to connect them)

#### Example Jenkinsfile (stripped down from msft-pipeline with all the features we use)

#### Advanced features and how to use them (Jenkinsfile examples)
* Parameters
* Options
* Stashing
* Archiving
* Unit tests
* Skipping stages

### Jenkins Master Node

* Ubuntu 16.04 LTS Xenial
* Jenkins stable version 2.89
* Jenkins Blue Ocean Plugin version 1.3.5
* Java 1.8

You can find the steps to install and configure Jenkins at
https://github.com/victormegherea/test_s/blob/master/install_jenkins_ubuntu/install_jenkins_ubuntu16.sh .

### Git repository

The git repository needs to contain a file named Jenkinsfile in the repository root, which contains a pipeline script.

### Jenkins Linux Slaves
TBD

### Jenkins Windows Slave

#### Installation
It is mandatory to run the Jenkins slave as a service on Windows and have the installed Java version as the one from the Jenkins master.
Otherwise the Windows slave connection to the master will show arbitrary disconnects that will lead to the whole pipeline failing.

#### Windows packages/folders required:
  * Hyper-V module needs to be installed and enabled
  * A Hyper-V switch named "External" needs to be created so that VMs have Internet access
  * A folder C:\workspace needs to be created, with full access for the LocalSystem user
  * A folder C:\bin needs to be created, with full access for the LocalSystem user

#### Windows external tools required (need to be added to the system path):
  * java.exe - downloadable from https://java.com/en/download/
  * git.exe - downloadable from https://git-scm.com/download/win
  * ssh.exe - already in the <git_installation_folder>/usr/bin
  * scp.exe - already in the <git_installation_folder>/usr/bin
  * icaserial.exe - source code downloadable from https://github.com/LIS/lis-test/tree/master/WS2008R2/lisa/Tools/icaserial
  * qemu-img.exe and the required .dlls - downloadable from https://cloudbase.it/downloads/qemu-img-win-x64-2_3_0.zip

### Example Jenkinsfile

### Advanced features

#### Parameters

Declarative Pipeline supports parameters out-of-the-box allowing the Pipeline to accept user-specified
parameters at runtime via the parameters directive.

#### Setting environment variables

An environment directive used in the top-level of the pipeline will apply to all steps within the pipeline.

#### Options

The options directive allows configuring Pipeline-specific options from within the Pipeline itself.
overrideIndexTriggers  allows overriding default treatment of branch indexing triggers.

#### Stages

The stages directive, and steps directive are required for a valid Declarative Pipeline as they instruct
Jenkins what to execute and in which stage it should be executed.

#### Parallel stages

The parallel directive allows stages to run at the same time.

#### Stashing

You can stash some files to be used later in the build, generally on another node/workspace.
Stashed files are discarded at the end of the build. Unstash restores a set of files previously stashed into the current workspace.

#### Archiving

archiveArtifacts captures the files built matching the include pattern and saves them in the Jenkins master for later retrieval.

#### Unit tests

Jenkins has a number of test recording, reporting, and visualization facilities provided by plugins. When there are test failures,
it is useful to have Jenkins record the failures for reporting and visualization in the web UI.

#### Skipping stages

You can skip stages with “when” directive that determine whether the stage should be executed or not depending on the given condition.

### Stages naming

* build_artifacts
* publish_temp_artifacts
* boot_test
* publish_artifacts
* validation
  - validation_functional
    - validation_functional_hyperv
    - validation_functional_azure
  - validation_perf
    - validation_perf_hyperv
    - validation_perf_azure
