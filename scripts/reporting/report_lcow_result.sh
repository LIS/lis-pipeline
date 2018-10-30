#!/bin/bash

set -xe -o pipefail

function main {
    REPORT_DIR=""
    DB_CONFIG=""
    SCRIPT_PATH="$(dirname $0)"
    PARSER_PATH="${SCRIPT_PATH}/parser.py"
    
    while true;do
        case "$1" in
            --report_dir)
                REPORT_DIR="$(readlink -e $2)"
                shift 2;;
            --db_config)
                DB_CONFIG="$(readlink -e "$2")"
                shift 2;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    
    if [[ ! -e "$REPORT_DIR" ]];then
        echo "Cannot find report directory"
        exit 1
    fi  
    if [[ ! -e "$DB_CONFIG" ]];then
        echo "Cannot fir DB config file"
        exit 1
    fi
    
    JSON_REPORTS=$(find $REPORT_DIR -name "*.json")
    
    for report in $JSON_REPORTS;do
        echo "Uploading: $(basename $report)"
        python "$PARSER_PATH" --test_results "${report}" --db_config "${DB_CONFIG}" \
            --composite_keys "BuildNumber,TestStage"
    done
}

main $@