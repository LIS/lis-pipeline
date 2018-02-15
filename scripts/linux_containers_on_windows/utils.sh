check_destination_dir() {
    dest_folder=$1
    
    if [[ ! -d "$dest_folder" ]] || [[ ! -d "${dest_folder}/$os_package" ]];then
        sudo mkdir -p "${dest_folder}/$os_package"
        echo "${dest_folder}/$os_package"
    else
        index=1
        while [[ -d "${dest_folder}-$index" ]] && [[ -d "${dest_folder}-${index}/$os_package" ]];do
            let index=index+1
        done
        sudo mkdir -p "${dest_folder}-$index/$os_package"
        echo "${dest_folder}-$index/$os_package"
    fi
}

copy_artifacts() {
    artifacts_folder=$1
    destination_path=$2
    
    atifact_exists="$(ls $artifacts_folder/* || true)"
    if [[ "$atifact_exists" != "" ]];then
        sudo cp "$artifacts_folder"/* "$destination_path"
    fi
}

exec_with_retry () {
    CMD=$1
    MAX_RETRIES=${2-10}
    INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL $CMD
}

pushd() {
    command pushd "$@" > /dev/null
}

popd() {
    command popd "$@" > /dev/null
}

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

function get_job_number (){
    #
    # Multiply current number of threads with a number
    # Usage:
    #   ./build_artifacts.sh --thread_number x10
    #
    multi="${1#*x}"
    cores="$(cat /proc/cpuinfo | grep -c processor)"
    result="$(expr $cores*$multi | bc)"
    echo ${result%.*}
}
