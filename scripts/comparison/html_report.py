import os

class htmlReport:
	htmlSections = []

	def add(self, section):
		self.htmlSections += section

	def create(self, resultName):
		with open(os.path.join(os.getcwd(), resultName), 'w') as file:
			for section in self.htmlSections:
				file.write(section)

class htmlReportSection:
	nextIndex = 0
	htmlParts = []

	def __init__(self, **kwargs):
		wrapper = kwargs['wrapper']
		for wrapp in wrapper:
			self.htmlParts.append(wrapp)
		self.nextIndex += int(len(wrapper)/2)

	def add(self, part, variables=[]):
		with open(part, 'r') as file:
			rawPart = file.read()
		for variable in variables:
 			rawPart = rawPart.replace("%" + variable["name"] + "%", variable["value"])
		self.htmlParts.insert(self.nextIndex, rawPart)
		self.nextIndex += 1

	def get(self):
		return self.htmlParts
