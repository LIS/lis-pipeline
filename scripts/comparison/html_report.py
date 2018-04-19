import os


class HtmlReport:
    html_sections = []

    def add(self, section):
        self.html_sections += section

    def create(self, result_name):
        with open(os.path.join(os.getcwd(), result_name), 'w') as file:
            for section in self.html_sections:
                file.write(section)


class HtmlReportSection:

    def __init__(self, **kwargs):
        self.next_index = 0
        self.html_parts = []
        wrapper = kwargs['wrapper']
        for wrapp in wrapper:
            self.html_parts.append(wrapp)
        self.next_index += int(len(wrapper)/2)

    def add(self, part, variables=[]):
        with open(part, 'r') as file:
            raw_part = file.read()
        for variable in variables:
            raw_part = raw_part.replace("%" + variable["name"] + "%",
                                      variable["value"])
        self.html_parts.insert(self.next_index, raw_part)
        self.next_index += 1

    def addrow(self, str):
        self.html_parts.insert(self.next_index, str)
        self.next_index += 1

    def get(self):
        return self.html_parts
