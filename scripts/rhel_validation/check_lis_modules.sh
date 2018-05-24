#!/bin/bash


main() {
    LIS_MODULES=(hv_vmbus hv_balloon hyperv_keyboard hv_netvsc hid_hyperv \
                 hv_utils hyperv_fb hv_storvsc pci_hyperv)
    UNSET_MOD=()
    MISSING_MOD=()
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
    printf "\nLoaded LIS modules after modprobe:\n"
    for module in ${UNSET_MOD[@]};do
        mod_out=$(modprobe $module)
        mod_exit=$?
        lsmod | grep "${module} " > /dev/null
        mod_found=$?
        if [[ $mod_exit -eq 0 ]] && [[ $mod_found -eq 0 ]];then
            mod_ver="$(modinfo $module | grep -w version)"
            mod_ver=${mod_ver#*:}
            printf "\n${module}: ${mod_ver}\n"
            if [[ "$mod_out" != "" ]];then
                printf "modprobe output:\n${mod_out}\n\n"
            fi
        else
            MISSING_MOD[${#MISSING_MOD[@]}]="$module"
        fi
    done
    if [[ ${#MISSING_MOD[@]} -ne 0 ]];then
        printf "\nCannot load modules:\n"
        for module in ${MISSING_MOD[@]};do
            echo "$module"
        done
    fi
}

main $@
