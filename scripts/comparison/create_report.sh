#!/bin/bash

set -xe

BASE_DIR=$(dirname $0)

HTML_REP_SCRIPT="${BASE_DIR}/html_parser.py"

parse_logs() {
    base_logs="$1"
    comp_logs="$2"
    metadata="$3"
    test_type="$4"
    
    if [[ "$test_type" == "" ]];then
        test_type="functional"
    fi
    
    python2 "${MANUAL_PARSER}" --logs_path "$base_logs" \
        --test_type "$test_type" \
        --output "./Patched.csv"
    parser_parameters="--test_results ./Patched.csv"
    if [[ "$comp_logs" != "" ]];then
        python2 "${MANUAL_PARSER}" --logs_path "$comp_logs" \
            --test_type "$test_type" \
            --output "./Unpatched.csv"
            parser_parameters+=" --comparison_results ./Unpatched.csv"
    fi
    
    if [[ "$metadata" != "" ]];then
        parser_parameters+=" --metadata ${metadata}"
    fi
    if [[ "$test_type" != "" ]];then
        parser_parameters+=" --test_type ${test_type}"
    fi
    
    python3 "$HTML_REP_SCRIPT" $parser_parameters --output temp_results.html
}

main() {
    while true;do
        case "$1" in
            --func_path)
                FUNC_PATH="$2" 
                shift 2;;
            --func_comp_path)
                FUNC_COMP_PATH="$2"
                shift 2;;
            --perf_path)
                PERF_PATH="$2" 
                shift 2;;
            --perf_comp_path)
                PERF_COMP_PATH="$2"
                shift 2;;
            --metadata_path)
                META_PATH="$2"
                shift 2;;
            --perf_test_type)
                TEST_TYPE="$2"
                shift 2;;
            --output)
                OUTPUT="$2"
                shift 2;;
            *) break ;;
        esac
    done
    
    git clone https://github.com/LIS/lis-test.git
    MANUAL_PARSER="./lis-test/WS2012R2/lisa/Infrastructure/lisa-parser/lisa_parser/manual_parser.py"
    
    
    if [[ -e "$OUTPUT" ]];then
        rm -f "$OUTPUT"
    fi
    
    if [[ "$FUNC_PATH" != "" ]];then
        parse_logs "$FUNC_PATH" "$FUNC_COMP_PATH" "$META_PATH"
        cat "temp_results.html" > "$OUTPUT"
        if [[ "$PERF_PATH" != "" ]];then
            parse_logs "$PERF_PATH" "$PERF_COMP_PATH" "" "$TEST_TYPE"
            cat "temp_results.html" >> "$OUTPUT"
        fi
    elif [[ "$PERF_PATH" != "" ]];then
        parse_logs "$PERF_PATH" "$PERF_COMP_PATH" "$META_PATH" \
                   "$TEST_TYPE"
        cat "temp_results.html" > "$OUTPUT"
    fi
}

main $@
