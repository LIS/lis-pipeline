#!/bin/bash

set -xe

BASE_DIR=$(dirname $0)
MANUAL_PARSER="./lis-test/WS2012R2/lisa/Infrastructure/lisa-parser/lisa_parser/manual_parser.py"
LISA_REPO="https://github.com/LIS/lis-test.git"

parse_logs() {
    local base_logs="$1"; shift
    local test_type="$1"

    echo "$base_logs"
    echo "$test_type"

    python2 "${MANUAL_PARSER}" --logs_path "$base_logs" \
        --test_type "$test_type" \
        --output "./perf_result.csv"
}

get_field () {
    local test_type="$1"; shift
    local io_mode="$1"

    case "$test_type" in
        "sr-iov_tcp")
            echo "3";;
        "sr-iov_udp")
            echo "3";;
        "fio_raid")
            case "$io_mode" in
                "read")
                    echo "5";;
                "randread")
                    echo "8";;
                "write")
                    echo "7";;
                "randwrite")
                    echo "6";;
                *)
                    echo "bad io mode"
                    exit 1;;
            esac;;
        *)
            echo "bad test_type"
            exit 1;;
    esac

}

get_final_result() {
    local field="$1"; shift
    local output="$1"

    final_result=$(cat ./perf_result.csv | tail -1 | cut -f $field -d ',')
    echo $final_result > perf_result
}

main() {
    while true;do
        case "$1" in
            --perf_path)
                PERF_PATH="$2"
                shift 2;;
            --perf_test_type)
                TEST_TYPE="$2"
                shift 2;;
            --io_mode)
                IO_MODE="$2"
                shift 2;;
            --output)
                OUTPUT="$2"
                shift 2;;
            *) break ;;
        esac
    done

    rm -rf lis-test || true
    git clone "$LISA_REPO" --depth 1

    if [[ -e "$OUTPUT" ]];then
        rm -f "$OUTPUT"
    fi

    parse_logs "$PERF_PATH" "$TEST_TYPE"
    field=$(get_field "$TEST_TYPE" "$IO_MODE")

    get_final_result "$field" "$OUTPUT"
}

main $@
