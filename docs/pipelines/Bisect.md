## Linux Kernel Bisect Pipeline

### Description

Linux Kernel Bisect Pipeline purpose is to find the commit that introduced a bug or a performance degradation in the Linux kernel.

### User interface options

When launching the pipeline, one can choose from the following options:

  - Choice of kernel source from the following options:
      - git://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git (default option)
      - https://git.kernel.org/pub/scm/linux/kernel/git/davem/net-next.git
      - git://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-azure
      - azure_kernel (an alias for a specific kernel)
  - Input field for the kernel source git branch (default value is "master"). This input field is mandatory.
  - Input field for the good commit. This input field is mandatory.
  - Input field for the bad commit (default value is HEAD). This input field is mandatory and cannot be the good commit.
  - Choice of OS distros from the following options:
      - Ubuntu_18.04.1 (default option)
      - CentOS_7.5
  - Choice of bisect type from the following options:
      - Boot (default option)
      - Functional
      - Performance
  - Choice of Azure flavor size from the following options:
      - Standard_A2 (default option)
      - Standard_E64_v3
      - Standard_F72s_v2
 - Input field for the test case name. If bisect type is Functional or Performance, this input field is mandatory. If the bisect type is Boot, this input field is not applied.
 - Input field for performance variation (the percentage of minimum performance drop in comparison to the good commit). This value must be specified as an integer. If bisect type is Performance,  this input field is mandatory.

### Implementation

The implementation will consist out of the bisect launcher pipeline and the bisect runner pipeline.

The bisect launcher pipeline is the one that has the user interface, has the bisect logic and triggers the bisect runner pipeline for each individual commit.

The user MUST use only the bisect launcher pipeline.

### Bisect Launcher Pipeline

### Bisect Runner Pipeline