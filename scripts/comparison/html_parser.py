import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

from html_utils import ComparisonTable
from html_utils import FileStructure
from html_utils import HtmlFile
from html_utils import HtmlTable
from html_utils import HtmlTag

FUNCTIONAL_COMPARISON = 'Patched == "Pass"'
PERFORMANCE_COMPARISON = 'Patched <= Unpatched'

LISAV2_PATCHED_SUITE = "LISAv2Patched-"
LISAV2_UNPATCHED_SUITE = "LISAv2Unpatched-"


def get_params():
    parser = argparse.ArgumentParser()
    parser.add_argument("--junit_test_results",
                        help="--junit_test_results <junit xml>")
    parser.add_argument("--patched_perf_dir",
                        help="--patched_perf_dir directory")
    parser.add_argument("--unpatched_perf_dir",
                        help="--unpatched_perf_dir directory")
    parser.add_argument("--output",
                        help="--output <outputhtml>")
    params = parser.parse_args()

    if not os.path.isfile(params.junit_test_results):
        sys.exit("You need to specify an existing junit test results path")
    if not params.output:
        sys.exit("You need to specify output path")

    return params


def parse_junit_results(results_path):
    all_results = {}

    tree = ET.parse(results_path)
    root = tree.getroot()

    for test_suite in root.iter('testsuite'):
        results = []
        test_suite_name = test_suite.attrib.get("name")
        index = 1
        if "LISAv2Patched-" in test_suite_name:
            test_suite_name_short = test_suite_name.replace(
                                       LISAV2_PATCHED_SUITE, "")
            if not all_results.get(test_suite_name_short):
                all_results[test_suite_name_short] = []
                index = 0
            all_results[test_suite_name_short].append(test_suite_name)
        else:
            test_suite_name_short = test_suite_name.replace(
                                       LISAV2_UNPATCHED_SUITE, "")
            if not all_results.get(test_suite_name_short):
                all_results[test_suite_name_short] = []
                index = 0
            all_results[test_suite_name_short].append(test_suite_name)
        for test_case in test_suite.iter("testcase"):
            test_case_name = test_case.attrib.get("name")
            test_case_time = test_case.attrib.get("time")
            test_case_status = "Pass"
            if test_case.findall("failure") or test_case.findall("error"):
                test_case_status = "Fail"
            results.append({
                "TestResult": test_case_status,
                "TestName": test_case_name,
                "TestTime": test_case_time,
            })
        all_results[test_suite_name_short][index] = results
    return all_results


def parse_perf_results(dir_path):
    all_results = {}

    if not dir_path:
        return all_results

    if not os.path.isdir(dir_path):
        print("Skip parsing perf results")
        return all_results

    for file in os.listdir(dir_path):
        if file.endswith(".json"):
            file_name_split = file.split("SUITE")
            if len(file_name_split) != 2:
                print("File name does not contain SUITE in it")
                return
            test_suite_name = file_name_split[0]
            test_case_name = file_name_split[1].replace("_perf_results.json", "")
            if not all_results.get(test_suite_name):
                all_results[test_suite_name] = []
            with open(os.path.join(dir_path, file)) as f:
                test_results = json.load(f)
                if type(test_results) is dict:
                    test_results = [test_results]
                for test_result in test_results:
                    test_result["TestName"] = test_case_name
                    for meta_key in test_result["meta_data"].keys():
                        test_result["TestName"] += ";" + meta_key + "=" + test_result["meta_data"][meta_key]
                    del test_result["meta_data"]
                    all_results[test_suite_name].append(test_result)
    return all_results

if __name__ == "__main__":
    params = get_params()
    test_results = parse_junit_results(params.junit_test_results)
    all_patched_perf_results = parse_perf_results(params.patched_perf_dir)
    all_unpatched_perf_results = parse_perf_results(params.unpatched_perf_dir)

    new_file = HtmlFile()
    meta_table = HtmlTable(cellspacing="0")

    if test_results.keys() or all_patched_perf_results.keys():
        metadata = [
            {
                "name": "Test suites",
                "value": ", ".join(test_results.keys())
            },
            {
                "name": "Perf Test suites",
                "value": ", ".join(all_patched_perf_results.keys())
        }]
        for key in metadata:
            cell_style = "border: 1px solid"
            new_row = meta_table.add_row()
            meta_table.add_cell_to_row(new_row, key["name"], style=cell_style)
            meta_table.add_cell_to_row(new_row, key["value"],
                                       style=cell_style)
        new_file.add_section(title=None, section=meta_table.get_table())

    ### FUNCTIONAL TESTS COMPARISON
    for key in test_results.keys():
        patched_results = test_results[key][0]
        unpatched_results = []
        if len(test_results[key]) > 1:
            unpatched_results = test_results[key][1]
        structure = FileStructure(comp_keys=[],
                                  comp_sub_keys=[],
                                  sections=dict(),
                                  sections_order=[])

        structure.comp_keys = ["TestResult", "TestTime"]
        structure.comp_sub_keys = ["Patched", "Unpatched"]
        structure.sections[key] = dict()
        structure.sections[key]["table1"] = ["TestName", "TestResult",
                                             "TestTime"]
        structure.sections_order.append(key)

        data_sets = []
        sub_keys = []
        for index in range(0, len(patched_results)):
            if unpatched_results:
                data_sets.append({
                    structure.comp_sub_keys[0]: patched_results[index],
                    structure.comp_sub_keys[1]: unpatched_results[index]
                })
                sub_keys = structure.comp_sub_keys
            else:
                data_sets.append({None: patched_results[index]})
                sub_keys = None

        for section in structure.sections_order:
            new_section = HtmlTag("div", style="padding: 5px")
            tables = structure.sections[section]
            for table in tables.keys():
                table_style = 'display: inline-table'
                new_table = ComparisonTable(tables[table], cellspacing="0",
                                            style=table_style)
                new_table.add_sub_keys(structure.comp_keys, sub_keys)
                new_table.create_key_cells()
                new_table.add_comparison_method(keys=tables[table][1],
                                                method=FUNCTIONAL_COMPARISON)
                for data_set in data_sets:
                    new_table.create_data_row(data_set)
                new_section.add_inner_tag(new_table.get_table())
            new_file.add_section(title=section, section=new_section)

    ### PERFORMANCE TESTS COMPARISON
    for key in all_patched_perf_results.keys():
        patched_perf_results = all_patched_perf_results.get(key)
        unpatched_perf_results = all_unpatched_perf_results.get(key)

        structure = FileStructure(comp_keys=[],
                                  comp_sub_keys=[],
                                  sections=dict(),
                                  sections_order=[])
        structure.comp_keys = list(patched_perf_results[0].keys())
        structure.comp_keys.remove("TestName")
        structure.comp_keys.sort(reverse=True)
        structure.comp_sub_keys = ["Patched", "Unpatched"]
        structure.sections[key] = dict()
        structure.sections[key]["table2"] = list(patched_perf_results[0].keys())
        structure.sections[key]["table2"].remove("TestName")
        structure.sections[key]["table2"].sort(reverse=True)
        structure.sections[key]["table2"] = ["TestName"] + structure.sections[key]["table2"]
        structure.sections_order.append(key)

        data_sets = []
        sub_keys = []
        for index in range(0, len(patched_perf_results)):
            if unpatched_perf_results:
                data_sets.append({
                    structure.comp_sub_keys[0]: patched_perf_results[index],
                    structure.comp_sub_keys[1]: unpatched_perf_results[index]
                })
                sub_keys = structure.comp_sub_keys
            else:
                data_sets.append({None: patched_perf_results[index]})
                sub_keys = None

        for section in structure.sections_order:
            new_section = HtmlTag("div", style="padding: 5px")
            tables = structure.sections[section]
            for table in tables.keys():
                table_style = 'display: inline-table'
                new_table = ComparisonTable(tables[table], cellspacing="0",
                                            style=table_style)
                new_table.add_sub_keys(structure.comp_keys, sub_keys)
                new_table.create_key_cells()
                new_table.table_keys = structure.sections[key]["table2"]
                new_table.add_comparison_method(keys=tables[table][1],
                                                method=PERFORMANCE_COMPARISON)
                for data_set in data_sets:
                    new_table.create_data_row(data_set)
                new_section.add_inner_tag(new_table.get_table())
            new_file.add_section(title=section, section=new_section)


    new_file.write(params.output)
