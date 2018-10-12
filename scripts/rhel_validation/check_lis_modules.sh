#!/bin/bash


main() {
    KERNEL_VERSION="$(uname -r)"

    printf "Running kernel version: ${KERNEL_VERSION}\n\n"

    LIS_MODULES=(hv_vmbus hv_balloon hyperv_keyboard hv_netvsc hid_hyperv \
                 hv_utils hyperv_fb hv_storvsc pci_hyperv)
    if [[ "$(lsb_release -r | grep "6")" ]];then
            LIS_MODULES=(hv_vmbus hv_balloon hyperv_keyboard hv_netvsc hid_hyperv \
                 hv_utils hyperv_fb hv_storvsc)
    fi
    
    UNSET_MOD=()

    printf "Loaded LIS Modules after reboot:\n"
    for module in ${LIS_MODULES[@]};do
        lsmod | grep "${module} " > /dev/null
        mod_found=$?
        if [[ $mod_found -eq 0 ]];then
            mod_ver="$(modinfo $module | grep -w version)"
            mod_ver=${mod_ver#*:}
            echo "${module}: ${mod_ver}"
        else
            UNSET_MOD[${#UNSET_MOD[@]}]="$module"
        fi
    done
    if [[ ${#UNSET_MOD[@]} -ne 0 ]];then
        printf "\nLoaded LIS modules after modprobe:\n"
    fi
    for module in ${UNSET_MOD[@]};do
        dmesg --clear
        mod_out=$(modprobe $module)
        mod_exit=$?
        mod_log="$(dmesg)"
        lsmod | grep "${module} " > /dev/null
        mod_found=$?
        if [[ $mod_exit -eq 0 ]] && [[ $mod_found -eq 0 ]];then
            mod_ver="$(modinfo $module | grep -w version)"
            mod_ver=${mod_ver#*:}
            printf "${module}: ${mod_ver}\n"
            if [[ "$mod_out" != "" ]];then
                printf "modprobe output:\n${mod_out}\n\n"
            fi
        else
            FAILED_MOD="${module} \n"
            if [[ "$mod_out" != "" ]];then
                FAILED_MOD+="modprobe output: \n${mod_out}\n"
            fi
            if [[ "$mod_log" != "" ]];then
                FAILED_MOD+="dmesg output: \n${mod_log}\n"
            fi
            FAILED_MOD+="\n"
        fi
    done
    if [[ "$FAILED_MOD" != "" ]];then
        printf "\nCannot load modules:\n"
        printf "$FAILED_MOD"
    fi
}

main $@
