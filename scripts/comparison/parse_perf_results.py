#!/usr/bin/python2.7

import sys
import argparse
import os
import glob
from html_report import HtmlReportSection, HtmlReport
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
    args = parser.parse_args()
    
    logs_path = args.logspath
    compare_path = args.comparewith
    output_file = args.output
    test_type = args.testtype
    
    if os.path.isdir(logs_path):
        return logs_path, output_file, test_type, compare_path


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


def order_table(log_table, key):
    ordered_table = []

    while log_table:
        min = log_table[0][key]
        min_obj = log_table[0]
        for line in log_table:
            if line[key] < min:
                min = line[key]
                min_obj = line

        ordered_table.append(min_obj)
        log_table.remove(min_obj)
    return ordered_table


if __name__ == "__main__":
    logs_path, output_file, test_type, compare_path = get_parameters()
    script_path = os.path.dirname(os.path.realpath(__file__))

    new_html = HtmlReport()

    main_parsed_logs, tables = parse_logs(logs_path, test_type)
    if compare_path:
        if os.path.isdir(compare_path):
            compare_parsed_logs, tables = parse_logs(compare_path, test_type)

    result_keys = []
    for line in main_parsed_logs:
        for key in line.keys():
            if key not in result_keys:
                result_keys.append(key)

    if compare_path:
        for table in tables:
            new_html.add(['<table cellpadding="0" cellspacing="0"'
                         'style="padding-top: 50px">\n'])

            first_row = HtmlReportSection(wrapper=
                ['<tr style="text-align:center">\n', '</tr>\n'])
            first_row.addrow('<td></td>\n')
            for index in range(1, len(table)):
                first_row.addrow('<td colspan="2" style="border:1px solid">&nbsp;' +
                                table[index] + '&nbsp;</td>\n')
            new_html.add(first_row.get())

            first_row = HtmlReportSection(
                wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
            first_row.addrow('<td style="border:1px solid">&nbsp;' +
                            table[0] + '&nbsp;</td>\n')
            for index in range(1, len(table)):
                first_row.addrow('<td style="border:1px solid">&nbsp;'
                                'Patched&nbsp;</td>\n')
                first_row.addrow('<td style="border:1px solid">&nbsp;'
                                'Unpatched&nbsp;</td>\n')
            new_html.add(first_row.get())

            for index in range(0, len(main_parsed_logs)):
                if (float(main_parsed_logs[index][table[1]]) < 
                        float(compare_parsed_logs[index][table[1]])) :
                    back_color = '#f75959'
                else:
                    back_color = '#8df972'
                new_row = HtmlReportSection(
                    wrapper=['<tr style="text-align:center;background-color:' +
                             back_color + '">\n', '</tr>\n'])
                new_row.addrow('<td style="border:1px solid">' +
                              str(main_parsed_logs[index][table[0]]) +
                              '</td>\n')
                for i in range(1, len(table)):
                    new_row.addrow('<td style="border:1px solid">&nbsp;' +
                                   str(main_parsed_logs[index][table[i]]) +
                                   '&nbsp;</td>\n')
                    new_row.addrow('<td style="border:1px solid">&nbsp;' +
                                  str(compare_parsed_logs[index][table[i]]) +
                                  '&nbsp;</td>\n')
                new_html.add(new_row.get())
            new_html.add(['</table>'])
    else:
        for table in tables:
            new_html.add(['<table cellpadding="0" cellspacing="0"'
                         'style="padding-top: 50px">\n'])
            first_row = HtmlReportSection(wrapper=['<tr>\n', '</tr>\n'])
            for key in table:
                first_row.addrow('<td style="border:1px solid">&nbsp;' +
                                key + '&nbsp;</td>\n')
            new_html.add(first_row.get())

            for line in main_parsed_logs:
                new_row = HtmlReportSection(
                    wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
                for key in table:
                    new_row.addrow('<td style="border:1px solid">' +
                                   str(line[key]) + '</td>\n')
                new_html.add(new_row.get())
            new_html.add(['</table>'])

    new_html.create(output_file)
