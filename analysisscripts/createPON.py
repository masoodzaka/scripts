
import heapq
import os


#### TO DO
# Add AFs of each file
# Look for exact SNP MATCH instead of just pos?

class vcfMerge():

    minCountThreshold = 1

    def __init__(self,path):

        try:
            #1. create priority queue
            self._heap = []
            self._output_file = open(path+'PON.tsv', 'w+')

        except Exception, err_msg:
            print "Error while creating Merger: %s" % str(err_msg)

    def merge(self, input_files):
        try:
            # open all files
            open_files = []
            [open_files.append(open(file__, 'r')) for file__ in input_files]

            [self.readFirstVariant(file__) for file__ in open_files]

            previousCount = 0
            smallest = self._heap[0]

            while(self._heap):

                previous = smallest[0]
                smallest = heapq.heappop(self._heap)

                if previous < smallest[0]:
                    self.writeToOutput(previous,previousCount)
                    previousCount = 1
                else:
                    previousCount += 1

                read_line = smallest[1].readline()
                self.pushVariantToHeap(read_line, smallest[1])

            self.writeToOutput(smallest[0], previousCount)

            [file__.close() for file__ in open_files]
            self._output_file.close()

        except Exception, err_msg:
            print "Error while merging: %s" % str(err_msg)

    def _delimiter_value(self):
        return "\n"

    def posToNumber(self,split):
        return int(split[0]) * 1e9 + int(split[1])

    def numberToPos(self, number):
        return str(int(number/1e9)) + "\t" + str(int(number%1e9))

    def readFirstVariant(self,file__):
        read_line = file__.readline()
        while read_line[0] == "#":
            read_line = file__.readline()
        self.pushVariantToHeap(read_line,file__)

    def pushVariantToHeap(self,read_line,file__):
        if(len(read_line) != 0):
            heapq.heappush(self._heap, (self.posToNumber(read_line.split("\t")), file__))

    def writeToOutput(self,posNumber,count):
        if count >= self.minCountThreshold:
            self._output_file.write(self.numberToPos(posNumber) + "\t" + str(count) + self._delimiter_value())

def getVCFList(path):
    files = []
    for x in os.listdir(path):
        if x[-4:] == ".vcf":
            files.append(path + x)
    return files

if __name__ == '__main__':
    path = "/Users/peterpriestley/hmf/analyses/PON/"
    files = getVCFList(path)
    merger = vcfMerge(path)
    merger.merge(files)


