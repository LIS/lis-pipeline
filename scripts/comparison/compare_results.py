#!/usr/bin/python3

import sys
import getopt
import os
import xml.etree.ElementTree as ET
from html_report import HtmlReportSection, HtmlReport
import glob
import configparser


def get_parameters(argv):
    outputFile = ''
    iniFile = ''
    try:
        opts, args = getopt.getopt(argv, "p:u:o:m:",
            ["patchedresults=", "unpatchedresults=", "output=", "metadata="])
    except getopt.GetoptError:
        print('compare_results.py --patchedtests <inputxml> ',
              '--unpatchedtests <inputxml> ',
              '--output <outputhtml> ',
              '--metadata <ini>')
        sys.exit(2)
    for opt, arg in opts:
        if opt in ("-p", "--patchedresults"):
            patchedResultsPath = arg
        elif opt in ("-u", "--unpatchedresults"):
            unpatchedResultsPath = arg
        elif opt in ("-o", "--output"):
            outputFile = arg
        elif opt in ("-m", "--metadata"):
            iniFile = arg

    iniFile = glob.glob(iniFile)
    patchedResultsPath = glob.glob(patchedResultsPath)
    unpatchedResultsPath = glob.glob(unpatchedResultsPath)

    if (os.path.isfile(patchedResultsPath[0]) and
            os.path.isfile(unpatchedResultsPath[0])):
        return patchedResultsPath[0], unpatchedResultsPath[0], iniFile, outputFile


def get_fixed_xml(xmlPath):
    fixedXml = ''
    with open(xmlPath, 'r') as file:
        xmlLines = file.readlines()
    for line in xmlLines:
        if '>...<' not in line:
            fixedXml += line
    tree = ET.fromstring(fixedXml)
    return tree


def clean_duplicates(testList):
    for test in testList:
        nr = testList.count(test)
        if nr > 1:
            for i in range(1, nr):
                testList.remove(test)
    return testList


def get_suite_data(testSuite):
    tests = []

    for child in testSuite:
        if (child.tag == 'testcase'):
            testResult = dict()
            testResult['name'] = child.attrib['name']
            testResult['time'] = child.attrib['time']
            failed = False
            failure = ''
            for prop in child:
                if (prop.tag == 'failure'):
                    failure = prop.text
                    failed = True
            if (failed):
                testResult['result'] = "Fail"
                testResult['failure'] = failure
            else:
                testResult['result'] = "Pass"
            tests.append(testResult)
    return tests


def get_metadata_from_ini(iniPath):
    entries = []
    try:
        config = configparser.ConfigParser()
        config.read(iniPath)
    except Exception:
        print('Cannot read ini file')

    if (config['METADATA']):
        for key in config['METADATA']:
            configEntry = dict()
            configEntry['name'] = key
            configEntry['value'] = config['METADATA'][key]
            entries.append(configEntry)
    return entries


def get_test_data(xmlPath):
    tests = []
    try:
        tree = ET.parse(xmlPath)
        root = tree.getroot()
    except ET.ParseError:
        root = get_fixed_xml(xmlPath)

    if (root.tag == 'testsuites'):
        for testSuite in root:
            tests += get_suite_data(testSuite)
    else:
        tests = get_suite_data(root)

    tests = clean_duplicates(tests)
    return tests


if __name__ == "__main__":
    patchedResultsPath, unpatchedResultsPath, iniFile, outputFile = get_parameters(sys.argv[1:])
    scriptPath = os.path.dirname(os.path.realpath(__file__))

    newHtml = HtmlReport()

    if (iniFile):
        metadata = get_metadata_from_ini(iniFile)
        metaSection = HtmlReportSection(
            wrapper=['<table cellpadding="0" cellspacing="0">\n',
                     '</table>\n'])
        for entry in metadata:
            metaSection.add(scriptPath + "/html/metarow.html", [
                {"name": "keyName", "value": entry['name']},
                {"name": "keyValue", "value": entry['value']}])
        newHtml.add(metaSection.get())

    patchedResults = get_test_data(patchedResultsPath)
    unpatchedResults = get_test_data(unpatchedResultsPath)

    newSection = HtmlReportSection(
            wrapper=['<table cellpadding="0" cellspacing="0" style="padding-top: 50px">',
                     '</table>'])
    newSection.add(scriptPath + "/html/head.html")

    for index in range(0, len(patchedResults)):
        resultsFound = False
        for ind in range(0, len(unpatchedResults)):
            if (patchedResults[index]['name'] == unpatchedResults[ind]['name']):
                patchedResult = patchedResults[index]
                unpatchedResult = unpatchedResults[ind]
                resultsFound = True
                break
        if (resultsFound):
            if (patchedResult['result'] == 'Fail' or
                    unpatchedResult['result'] == 'Fail'):
                backColor = '#f75959'
            else:
                backColor = '#8df972'
            newSection.add(scriptPath + "/html/row.html", [
                {"name": "testName",
                    "value": patchedResult['name']},
                {"name": "patchedResult",
                    "value": patchedResult['result']},
                {"name": "patchedTime",
                    "value": patchedResult['time']},
                {"name": "unpatchedResult",
                    "value": unpatchedResult['result']},
                {"name": "unpatchedTime",
                    "value": unpatchedResult['time']},
                {"name": "backColor",
                    "value": backColor}])

    newHtml.add(newSection.get())
    newHtml.create(outputFile)
