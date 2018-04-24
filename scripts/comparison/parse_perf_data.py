#!/usr/bin/python2.7

import argparse
import os
from perf_report import NTTTCPLogsReader, IPERFLogsReader, FIOLogsReaderRaid


def get_parameters():
    logs_path = ''
    output_file = ''
    test_type = ''
    compare_path = ''
    parser = argparse.ArgumentParser()
    parser.add_argument("--logspath", help="--logspath <path>")
    parser.add_argument("--comparewith", help="--unpatchedtests <path>")
    parser.add_argument("--output", help="--output <outputhtml>")
    parser.add_argument("--testtype", help="--testtype")
    parser.add_argument("--key", help="--key")
    args = parser.parse_args()

    logs_path = args.logspath
    compare_path = args.comparewith
    output_file = args.output
    test_type = args.testtype
    key = args.key

    if os.path.isdir(logs_path):
        return logs_path, output_file, test_type, compare_path, key

def order_table(log_table, key):
    ordered_table = []

    while (log_table):
        min = log_table[0][key]
        min_obj = log_table[0]
        for line in log_table:
            if line[key] < min:
                min = line[key]
                min_obj = line

        ordered_table.append(min_obj)
        log_table.remove(min_obj)
    return ordered_table


def parse_logs(logs_path, test_type):

    if test_type.lower() == 'tcp':
        parsed_perf_log = NTTTCPLogsReader(logs_path).process_logs()
        parsed_perf_log = order_table(parsed_perf_log, 'NumberOfConnections')
        tables = [['NumberOfConnections', 'Throughput_Gbps',
                   'AverageLatency_ms'],
                  ['NumberOfConnections', 'SenderCyclesPerByte',
                  'ReceiverCyclesPerByte', 'PacketSize_KBytes']]
    elif test_type.lower() == 'udp':
        parsed_perf_log = IPERFLogsReader(logs_path).process_logs()
        parsed_perf_log = order_table(parsed_perf_log, 'NumberOfConnections')
        tables = [['NumberOfConnections', 'TxThroughput_Gbps',
                   'RxThroughput_Gbps', 'DatagramLoss']]


    elif test_type.lower() == 'fio':
        parsed_perf_log = FIOLogsReaderRaid(logs_path).process_logs()
        parsed_perf_log = order_table(parsed_perf_log, 'QDepth')
        parsed_perf_log = order_table(parsed_perf_log, 'BlockSize_KB')
        tables = [['QDepth', 'rand-read:', 'BlockSize_KB'],
                  ['QDepth', 'rand-write:', 'BlockSize_KB'],
                  ['QDepth', 'seq-read:', 'BlockSize_KB'],
                  ['QDepth', 'seq-write:', 'BlockSize_KB'],
                  ['QDepth', 'rand-read: latency', 'BlockSize_KB'],
                  ['QDepth', 'rand-write: latency', 'BlockSize_KB'],
                  ['QDepth', 'seq-read: latency', 'BlockSize_KB'],
                  ['QDepth', 'seq-write: latency','BlockSize_KB']]

    return parsed_perf_log, tables


if __name__ == "__main__":
    logs_path, output_file, test_type, compare_path, key = get_parameters()
    keyA = {
            "TCP" : 'Throughput_Gbps',
            "UDP" : 'Throughput_Gbps',
            "FIO" : key
            }

    script_path = os.path.dirname(os.path.realpath(__file__))

    main_parsed_logs, tables = parse_logs(logs_path, test_type)
    if compare_path:
        if os.path.isdir(compare_path):
            compare_parsed_logs, tables = parse_logs(compare_path, test_type)

    result_keys = []
    for line in main_parsed_logs:
        for key in line.keys():
            if key not in result_keys:
                result_keys.append(key)

    print main_parsed_logs[0].get(keyA.get(test_type))
