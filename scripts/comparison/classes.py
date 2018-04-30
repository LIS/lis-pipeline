import os


def create_tag_style(**attr):
    style = ""
    for key in attr:
        style += key + ': ' + attr[key] + ';'
    return style


def add_identation(tag_list):
    idented_tag_list = []
    for line in tag_list:
        line = "\n    " + line[1:]
        idented_tag_list.append(line)
    return idented_tag_list


class fileStructure:
    def __init__(self, **entries):
        self.__dict__.update(entries)


class htmlTag:
    def __init__(self, tag, **attributes):
        self.tag = tag
        self.attributes = attributes
        self.data = ""

    def __iter__(self):
        if type(self.data) is str:
            raise StopIteration
        elif type(self.data) is list:
            self.iter_index = -1
            return self

    def __next__(self):
        if self.iter_index + 1 < len(self.data):
            self.iter_index += 1
            return self.data[self.iter_index]
        else:
            raise StopIteration

    def __len__(self):
        if type(self.data) is list:
            return len(self.data)
        else:
            return 0

    def __getitem__(self, index):
        if type(self.data) is list:
            return self.data[index]

    def add_inner_tag(self, inner_tag):
        if type(self.data) is str:
            self.data = []
        self.data.append(inner_tag)

    def add_inner_text(self, text):
        self.data = text

    def build_tag(self, data=None):
        line = "\n<" + self.tag
        for key in self.attributes.keys():
            line += ' ' + key + '="' + self.attributes[key] + '"'
        line += ">"
        if type(data) is str:
            line += data + "</" + self.tag + ">"
        return line

    def get_section(self):
        self.section = []
        if type(self.data) is str:
            self.section.append(self.build_tag(self.data))
        elif type(self.data) is list:
            self.section.append(self.build_tag())
            for inner_tag in self.data:
                self.section += add_identation(inner_tag.get_section())
            self.section.append("\n</" + self.tag + ">")
        return self.section


class htmlFile(htmlTag):
    def __init__(self):
        super().__init__("div")

    def add_section(self, **sec):
        section_title = htmlTag("b")
        section_title.add_inner_text(sec['title'])
        self.add_inner_tag(section_title)
        self.add_inner_tag(sec['section'])

    def write(self, output):
        with open(os.path.join(os.getcwd(), output), 'w') as output_file:
            for section in self.get_section():
                output_file.write(section)


class htmlTable:
    def __init__(self, **table_attributes):
        self.main_tag = htmlTag("table", **table_attributes)

    def add_cell_to_row(self, row, text=None, **cell_attributes):
        new_cell = htmlTag("td", **cell_attributes)
        new_cell.add_inner_text(text)
        row.add_inner_tag(new_cell)

    def add_row(self, **row_attributes):
        new_row = htmlTag("tr", **row_attributes)
        self.main_tag.add_inner_tag(new_row)
        return new_row

    def add_text(self, row, col, text):
        for row_index in range(0, len(self.main_tag)):
            row_tag = self.main_tag[row_index]
            for col_index in range(0, len(row_tag)):
                if row_index == row and col_index == col:
                    row_tag[col_index].add_inner_text(text)

    def get_table(self):
        return self.main_tag


class comparisonTable(htmlTable):
    def __init__(self, table_keys, **table_attributes):
        super().__init__(**table_attributes)
        self.table_keys = table_keys
        self.table_sub_keys = dict()
        for key in table_keys:
            self.table_sub_keys[key] = None
        self.comparison_keys = []

    def add_sub_keys(self, table_keys, sub_keys):
        for key in self.table_keys:
            if key in table_keys:
                self.table_sub_keys[key] = sub_keys

    def create_key_cells(self):
        keys_row = self.add_row()
        sub_key_row = self.add_row()
        for key in self.table_keys:
            if self.table_sub_keys[key]:
                for sub_key in self.table_sub_keys[key]:
                    self.add_cell_to_row(sub_key_row, sub_key,
                                         style="border: 1px solid")
                cs = str(len(self.table_sub_keys[key]))
                rs = "1"
            else:
                cs = "1"
                rs = "2"
            self.add_cell_to_row(keys_row, key, colspan=cs, rowspan=rs,
                                 style="border: 1px solid")

    def add_comparison_method(self, **params):
        self.comparison_keys = params["keys"]
        comp_met = params["method"]
        if "==" in comp_met:
            self.comp_op = "=="
        elif "<" in comp_met:
            self.comp_op = "<"
        elif ">" in comp_met:
            self.comp_op = ">"
        self.comp_args = []
        for arg in comp_met.split(self.comp_op):
            self.comp_args.append(arg.strip())

    def compare_data(self, data_set):
        result = True
        args = []
        key = self.comparison_keys
        for arg in self.comp_args:
            if '"' in arg:
                args.append(arg.strip('"'))
            else:
                args.append(data_set[arg][key])
        if self.comp_op == "==":
            result &= args[0] == args[1]
        elif self.comp_op == "<":
            result &= float(args[0]) < float(args[1])
        elif self.comp_op == ">":
            result &= float(args[0]) > float(args[1])
        return result

    def create_data_row(self, data_set):
        bg_color = '#ffffff'
        if len(data_set) > 1:
            if self.compare_data(data_set):
                bg_color = '#66ff66'
            else:
                bg_color = '#ff4d4d'
        data_row = self.add_row(style="background-color: " + bg_color)
        for key in self.table_keys:
            if self.table_sub_keys[key]:
                for sub_key in self.table_sub_keys[key]:
                    self.add_cell_to_row(data_row, data_set[sub_key][key],
                                         style="border: 1px solid")
            else:
                base_key = list(data_set.keys())[0]
                self.add_cell_to_row(data_row, data_set[base_key][key],
                                     style="border: 1px solid")
