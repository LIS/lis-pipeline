import argparse
import os
import sys
import xml.etree.ElementTree as ET

from html_utils import ComparisonTable
from html_utils import FileStructure
from html_utils import HtmlFile
from html_utils import HtmlTable
from html_utils import HtmlTag

FUNCTIONAL_COMPARISON = 'Patched == "Pass"'
LISAV2_PATCHED_SUITE = "LISAv2Patched-"
LISAV2_UNPATCHED_SUITE = "LISAv2Unpatched-"


def get_params():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test_results",
                        help="--test_results <input xml>")
    parser.add_argument("--output",
                        help="--output <outputhtml>")
    params = parser.parse_args()

    if not os.path.isfile(params.test_results):
        sys.exit("You need to specify an existing test results path")
    if not params.output:
        sys.exit("You need to specify output path")

    return params


def parse_junit_results(results_path):
    tree = ET.parse(results_path)
    root = tree.getroot()
    all_results = {}

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
            if test_case.findall("failure"):
                test_case_status = "Fail"
            results.append({
                "TestResult": test_case_status,
                "TestName": test_case_name,
                "TestTime": test_case_time,
            })
        all_results[test_suite_name_short][index] = results
    return all_results


if __name__ == "__main__":
    params = get_params()
    test_results = parse_junit_results(params.test_results)

    new_file = HtmlFile()
    meta_table = HtmlTable(cellspacing="0")
    metadata = [{
        "name": "Test suites",
        "value": ", ".join(test_results.keys())
    }]
    for key in metadata:
        cell_style = "border: 1px solid"
        new_row = meta_table.add_row()
        meta_table.add_cell_to_row(new_row, key["name"], style=cell_style)
        meta_table.add_cell_to_row(new_row, key["value"],
                                   style=cell_style)
    new_file.add_section(title=None, section=meta_table.get_table())

    for key in test_results.keys():
        patched_results = test_results[key][0]
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

    new_file.write(params.output)
