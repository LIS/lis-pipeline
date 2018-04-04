#!/usr/bin/python3

import sys
import argparse
import os
import xml.etree.ElementTree as ET
from html_report import HtmlReportSection, HtmlReport
import glob
import configparser


def get_parameters():
    output_file = ''
    ini_file = ''
    parser = argparse.ArgumentParser()
    parser.add_argument("--patchedresults", help="--patchedresults <inputxml>")
    parser.add_argument("--unpatchedresults", help="'--unpatchedresults <inputxml>")
    parser.add_argument("--output", help="--output <outputhtml>")
    parser.add_argument("--metadata", help="--meta_data <ini>")
    args = parser.parse_args()

    ini_file = glob.glob(args.metadata)
    patched_results_path = glob.glob(args.patchedresults)
    unpatched_results_path = glob.glob(args.unpatchedresults)
    output_file = args.output

    if (os.path.isfile(patched_results_path[0]) and
        os.path.isfile(unpatched_results_path[0]) and output_file):
        return patched_results_path[0], unpatched_results_path[0], ini_file, output_file


def get_fixed_xml(xml_path):
    fixed_xml = ''
    with open(xml_path, 'r') as file:
        xml_lines = file.readlines()
    for line in xml_lines:
        if '>...<' not in line:
            fixed_xml += line
    tree = ET.fromstring(fixed_xml)
    return tree


def clean_duplicates(test_list):
    for test in test_list:
        nr = test_list.count(test)
        if nr > 1:
            for i in range(1, nr):
                test_list.remove(test)
    return test_list


def get_suite_data(test_suite):
    tests = []

    for child in test_suite:
        if child.tag == 'testcase':
            test_result = dict()
            test_result['name'] = child.attrib['name']
            test_result['time'] = child.attrib['time']
            failed = False
            failure = ''
            for prop in child:
                if prop.tag == 'failure':
                    failure = prop.text
                    failed = True
            if failed:
                test_result['result'] = "Fail"
                test_result['failure'] = failure
            else:
                test_result['result'] = "Pass"
            tests.append(test_result)
    return tests


def get_meta_data_from_ini(ini_path):
    entries = []
    try:
        config = configparser.ConfigParser()
        config.read(ini_path)
    except Exception:
        print('Cannot read ini file')
        return ()

    if config['METADATA']:
        for key in config['METADATA']:
            config_entry = dict()
            config_entry['name'] = key
            config_entry['value'] = config['METADATA'][key]
            entries.append(config_entry)
    return entries


def get_test_data(xml_path):
    tests = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except ET.ParseError:
        root = get_fixed_xml(xmlPath)

    if root.tag == 'testsuites':
        for test_suite in root:
            tests += get_suite_data(test_suite)
    else:
        tests = get_suite_data(root)

    tests = clean_duplicates(tests)
    return tests


if __name__ == "__main__":
    patched_results_path, unpatched_results_path, ini_file, output_file = get_parameters()
    script_path = os.path.dirname(os.path.realpath(__file__))

    new_html = HtmlReport()

    if ini_file:
        meta_data = get_meta_data_from_ini(ini_file)
        meta_section = HtmlReportSection(
            wrapper=['<table cellpadding="0" cellspacing="0">\n',
                     '</table>\n'])
        for entry in meta_data:
            meta_section.add(script_path + "/html/metarow.html", [
                {"name": "keyName", "value": entry['name']},
                {"name": "keyValue", "value": entry['value']}])
        new_html.add(meta_section.get())

    patched_results = get_test_data(patched_results_path)
    unpatched_results = get_test_data(unpatched_results_path)

    new_section = HtmlReportSection(
            wrapper=['<table cellpadding="0" cellspacing="0" style="padding-top: 50px">',
                     '</table>'])
    new_section.add(script_path + "/html/head.html")

    for index in range(0, len(patched_results)):
        results_found = False
        for ind in range(0, len(unpatched_results)):
            if patched_results[index]['name'] == unpatched_results[ind]['name']:
                patched_result = patched_results[index]
                unpatched_result = unpatched_results[ind]
                results_found = True
                break
        if results_found:
            if (patched_result['result'] == 'Fail' or
                    unpatched_result['result'] == 'Fail'):
                back_color = '#f75959'
            else:
                back_color = '#8df972'
            new_section.add(script_path + "/html/row.html", [
                {"name": "testName",
                    "value": patched_result['name']},
                {"name": "patchedResult",
                    "value": patched_result['result']},
                {"name": "patchedTime",
                    "value": patched_result['time']},
                {"name": "unpatchedResult",
                    "value": unpatched_result['result']},
                {"name": "unpatchedTime",
                    "value": unpatched_result['time']},
                {"name": "backColor",
                    "value": back_color}])

    new_html.add(new_section.get())
    new_html.create(output_file)
