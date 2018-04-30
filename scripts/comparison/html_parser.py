from classes import fileStructure, htmlTag, htmlFile, htmlTable, comparisonTable
import argparse
import os
import configparser
import sys
import csv

functional_comparison = 'Patched == "Pass"'
perf_comparison = 'Patched > Unpatched'


def get_params():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test_results",
                        help="--test_results <input csv>")
    parser.add_argument("--comparison_results",
                        help="'--comparison_results <input csv>")
    parser.add_argument("--metadata",
                        help="--metadata <input ini>")
    parser.add_argument("--test_type")
    parser.add_argument("--output",
                        help="--output <outputhtml>")
    params = parser.parse_args()

    if not os.path.isfile(params.test_results):
        sys.exit("You need to specify an existing test results path")
    if (params.comparison_results and not
            os.path.isfile(params.comparison_results)):
        sys.exit("Comparsion results path does not exist")
    if (params.metadata and not os.path.isfile(params.metadata)):
        sys.exit("Metadata ini path does not exist")
    if not params.output:
        sys.exit("You need to specify output path")
    if not params.test_type:
        sys.exit("You need to specify a valid test type")

    return params


def get_structure_from_ini(ini_path):
    structure = fileStructure(comp_keys=[],
                              comp_sub_keys=[],
                              sections=dict())
    config = configparser.ConfigParser()
    config.read(ini_path)

    if config['Keys']:
        structure.comp_keys = config['Keys']['comparison_keys'].split(";")
        structure.comp_sub_keys = config['Keys']['comparison_sub_keys'].split(";")
    sections = list(config.keys())
    for section in sections[2:]:
        structure.sections[section] = dict()
        for table in config[section]:
            structure.sections[section][table] = config[section][table].split(";")

    return structure


def get_metadata_from_ini(ini_path):
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


def parse_csv_results(results_path):
    with open(results_path, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        results = []
        for row in reader:
            results.append(row)
    return results


if __name__ == "__main__":
    params = get_params()
    script_path = os.path.dirname(os.path.realpath(__file__))
    structure = get_structure_from_ini(script_path + '/ini_configs/' +
                                       params.test_type.lower() + '.ini')

    new_file = htmlFile()

    if params.metadata:
        metadata = get_metadata_from_ini(params.metadata)
        meta_table = htmlTable(cellspacing="0")
        for key in metadata.keys():
            cell_style = "border: 1px solid"
            new_row = meta_table.add_row()
            meta_table.add_cell_to_row(new_row, key, style=cell_style)
            meta_table.add_cell_to_row(new_row, metadata[key],
                                       style=cell_style)
        new_file.add_section(title=None, section=meta_table.get_table())

    test_results = parse_csv_results(params.test_results)
    comparison_results = []
    if params.comparison_results:
        comparison_results = parse_csv_results(params.comparison_results)

    data_sets = []
    sub_keys = []
    for index in range(0, len(test_results)):
        if comparison_results:
            data_sets.append({structure.comp_sub_keys[0]: test_results[index],
                        structure.comp_sub_keys[1]: comparison_results[index]})
            sub_keys = structure.comp_sub_keys
        else:
            data_sets.append({None: test_results[index]})
            sub_keys = None

    for section in structure.sections.keys():
        new_section = htmlTag("div", style="padding: 5px")
        tables = structure.sections[section]
        for table in tables.keys():
            table_style = 'display: inline-table; padding: 20px'
            new_table = comparisonTable(tables[table], cellspacing="0",
                                        style=table_style)
            new_table.add_sub_keys(structure.comp_keys, sub_keys)
            new_table.create_key_cells()
            if params.test_type == 'functional':
                new_table.add_comparison_method(keys=tables[table][1],
                                                method=functional_comparison)
            else:
                new_table.add_comparison_method(keys=tables[table][1],
                                                method=perf_comparison)
            for data_set in data_sets:
                new_table.create_data_row(data_set)
            new_section.add_inner_tag(new_table.get_table())
        new_file.add_section(title=section, section=new_section)

    new_file.write(params.output)
