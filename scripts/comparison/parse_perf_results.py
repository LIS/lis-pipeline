import sys
import getopt
import os
import glob
from html_report import htmlReportSection, htmlReport
from perf_report import NTTTCPLogsReader
import ConfigParser as configparser

def getParameters(argv):
    outputFile = ''
    iniFile = ''
    testType = ''
    comparePath = ''
    try:
        opts, args = getopt.getopt(argv, "l:o:m:t:c:",
            ["logspath=", "output=", "metadata=", "testtype=","comparewith="])
    except getopt.GetoptError:
        print('compare_results.py --logspath <path to logs>',
              '--output <outputhtml> ',
              '--metadata <ini>',
              '--comparewith <path to logs>')
        sys.exit(2)
    for opt, arg in opts:
        if opt in ("-l", "--logspath"):
            logsPath = arg
        elif opt in ("-o", "--output"):
            outputFile = arg
        elif opt in ("-m", "--metadata"):
            iniFile = arg
        elif opt in ("-t", "--testtype"):
            testType = arg
        elif opt in ("-c", "--comparewith"):
            comparePath = arg
    
    iniFile = glob.glob(iniFile)

    if (os.path.isdir(logsPath)):
        return logsPath, outputFile, testType, comparePath

def parse_logs(logsPath, testType):

    if (testType.lower() == 'tcp'):
        parsedPerfLog = NTTTCPLogsReader(logsPath).process_logs()
        parsedPerfLog = order_table(parsedPerfLog, 'NumberOfConnections')
        tables = [['NumberOfConnections', 'Throughput_Gbps', 'AverageLatency_ms'], 
            ['NumberOfConnections', 'SenderCyclesPerByte', 'ReceiverCyclesPerByte', 'PacketSize_KBytes']]
    
    return parsedPerfLog, tables
    
def order_table(logTable, key):
    orderedTable = []
    
    while (logTable):
        min = logTable[0][key]
        minObj = logTable[0]
        for line in logTable:
            if (line[key] < min):
                min = line[key]
                minObj = line
                
        orderedTable.append(minObj)
        logTable.remove(minObj)
    return orderedTable
        
    
    
if __name__ == "__main__":
    logsPath, outputFile, testType, comparePath = getParameters(sys.argv[1:])
    scriptPath = os.path.dirname(os.path.realpath(__file__))
    
    comparePath = logsPath ####################
    
    newHtml = htmlReport()
        
    mainParsedLogs, tables = parse_logs(logsPath, testType);
    if (os.path.isdir(comparePath)):
        compareParsedLogs, tables = parse_logs(comparePath, testType);
    
    resultKeys = []
    for line in mainParsedLogs:
        for key in line.keys():
            if (not key in resultKeys):
                resultKeys.append(key)

    if (os.path.isdir(comparePath)):
        for table in tables:
            newHtml.add(['<table cellpadding="0" cellspacing="0" style="padding-top: 50px">\n'])
            
            firstRow = htmlReportSection(wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
            firstRow.addrow('<td></td>\n')
            for index in range(1, len(table)):
                firstRow.addrow('<td colspan="2" style="border:1px solid">&nbsp;' + table[index] + '&nbsp;</td>\n')
            newHtml.add(firstRow.get())
            
            firstRow = htmlReportSection(wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
            firstRow.addrow('<td style="border:1px solid">&nbsp;' + table[0]+ '&nbsp;</td>\n')
            for index in range(1, len(table)):
                firstRow.addrow('<td style="border:1px solid">&nbsp;Patched&nbsp;</td>\n')
                firstRow.addrow('<td style="border:1px solid">&nbsp;Unpatched&nbsp;</td>\n')      
            newHtml.add(firstRow.get())
            
            for index in range(0, len(mainParsedLogs)):
                newRow = htmlReportSection(wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
                newRow.addrow('<td style="border:1px solid">' + str(mainParsedLogs[index][table[0]]) + '</td>\n')
                for i in range(1, len(table)):
                    newRow.addrow('<td style="border:1px solid">&nbsp;' + str(mainParsedLogs[index][table[i]]) + '&nbsp;</td>\n')
                    newRow.addrow('<td style="border:1px solid">&nbsp;' + str(compareParsedLogs[index][table[i]]) + '&nbsp;</td>\n')
                newHtml.add(newRow.get())
            newHtml.add(['</table>'])
    else:
        for table in tables:
            newHtml.add(['<table cellpadding="0" cellspacing="0" style="padding-top: 50px">\n'])
            firstRow = htmlReportSection(wrapper=['<tr>\n', '</tr>\n'])     
            for key in table:
                firstRow.addrow('<td style="border:1px solid">&nbsp;' + key + '&nbsp;</td>\n')
            newHtml.add(firstRow.get())
    
            for line in mainParsedLogs:
                newRow = htmlReportSection(wrapper=['<tr style="text-align:center">\n', '</tr>\n'])
                for key in table:
                    newRow.addrow('<td style="border:1px solid">' + str(line[key]) + '</td>\n')
                newHtml.add(newRow.get())
            newHtml.add(['</table>'])

    newHtml.create(outputFile)
