#!/bin/bash

exec_with_retry2 () {
    MAX_RETRIES=$1
    INTERVAL=$2

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        eval '${@:3}' || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

exec_with_retry () {
    CMD=$1
    MAX_RETRIES=${2-10}
    INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL $CMD
}

install_kernel () {
    local URLS; local BASEFILE
    URLS=(MagicURL)

    echo $URLS

    for URL in "${URLS[@]}"
    do
        echo ${URL}
        exec_with_retry "wget ${URL}" 3
        BASEFILE=$(basename ${URL})
        dpkg -i $BASEFILE
    done
}

main() {
    install_kernel
    reboot
}

main

exit 0
