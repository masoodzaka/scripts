library(tidyr)
library(dplyr)
library(RMySQL)
library(purple)
library(GenomicRanges)
library(BSgenome.Hsapiens.UCSC.hg19)


####### PREPARE DATA
load(file = "~/hmf/analysis/svPaper/cohort.RData")

allSvs = read.csv("/Users/jon/hmf/analysis/svPaper/SVA_SVS.csv")
mbcSvs = allSvs %>% filter(SampleId %in% multipleBiopsyCohort$sampleId)
save(mbcSvs, file = "~/hmf/analysis/svPaper/mbcSvs.RData")

doubleBiopsy = multipleBiopsyCohort %>% group_by(patientId) %>% filter(n() == 2) %>% mutate(n = row_number())
dbSvs = mbcSvs %>% filter(SampleId %in% doubleBiopsy$sampleId)

reformattedSVS = dbSvs %>% 
  select(sampleId = SampleId, startChromosome = ChrStart, endChromosome = ChrEnd, startPosition = PosStart, endPosition = PosEnd, startOrientation = OrientStart, endOrientation = OrientEnd, everything()) %>%
  left_join(doubleBiopsy %>% select(sampleId, n), by = "sampleId")

query = reformattedSVS %>% filter(n == 1)
subject = reformattedSVS %>% filter(n == 2)

save(query, subject, file = "~/hmf/analysis/svPaper/multipleBiopsy.RData")

####### ANALYSIS
sv_overlaps <- function(query, subject, maxgap = -1) {
  require(tidyr)
  require(dplyr)
  require(GenomicRanges)
  
  queryStartRange <- GRanges(paste0(query$patientId, query$startChromosome, query$startOrientation), IRanges(query$startPosition, query$startPosition))
  subjectStartRange <- GRanges(paste0(subject$patientId, subject$startChromosome, subject$startOrientation), IRanges(subject$startPosition, subject$startPosition))
  startOverlaps = data.frame(findOverlaps(queryStartRange, subjectStartRange, type="any", select="all", maxgap = maxgap))
  
  queryEndRange <- GRanges(paste0(query$patientId, query$endChromosome, query$endOrientation), IRanges(query$endPosition, query$endPosition))
  subjectEndRange <- GRanges(paste0(subject$patientId, subject$endChromosome, subject$endOrientation), IRanges(subject$endPosition, subject$endPosition))
  endOverlaps = data.frame(findOverlaps(queryEndRange, subjectEndRange, type="any", select="all", maxgap = maxgap))
  
  overlaps = inner_join(startOverlaps, endOverlaps, by = c("queryHits", "subjectHits"))
  
  overlapQueryData = query[overlaps$queryHits, ] %>%
    mutate(queryHits = overlaps$queryHits) %>%
    select(queryHits, sampleId, startChromosome, endChromosome, startPosition, endPosition, startOrientation, endOrientation)
  
  overlapSubjectData = subject[overlaps$subjectHits, ] %>%
    mutate(subjectHits = overlaps$subjectHits) %>%
    select(subjectHits, subjectStartPosition = startPosition, subjectEndPosition = endPosition, subjectStartOrientation = startOrientation, subjectEndOrientation = endOrientation)
  
  overlapsData = bind_cols(overlapQueryData, overlapSubjectData) %>%
    filter(startOrientation == subjectStartOrientation, endOrientation == subjectEndOrientation) %>%
    select(-subjectStartOrientation, -subjectEndOrientation) %>%
    mutate(startPositionDiff = abs(startPosition - subjectStartPosition), endPositionDiff = abs(endPosition - subjectEndPosition), positionDiff = startPositionDiff + endPositionDiff) %>%
    group_by(startChromosome, endChromosome, startPosition, endPosition,startOrientation,endOrientation) %>%
    top_n(1, -positionDiff) %>%
    group_by(queryHits) %>%
    top_n(1, -subjectHits)
  
  return (overlapsData %>% select(queryHits, subjectHits))
}

load(file = "~/hmf/analysis/svPaper/multipleBiopsy.RData")
overlaps = sv_overlaps(query, subject, 10)

subject$scope <- "Private"
query$scope <- "Private"
query$ClusterCountMatch <- NA
query$ClusterCountDesc <- NA

subject[overlaps$subjectHits, "scope"] <- "Shared"
query[overlaps$queryHits, "scope"] <- "Shared"

query[overlaps$queryHits, "ClusterCountMatch"] <- query[overlaps$queryHits, "ClusterCount"] == subject[overlaps$subjectHits, "ClusterCount"]
query[overlaps$queryHits, "ClusterDescMatch"] <- query[overlaps$queryHits, "ClusterDesc"] == subject[overlaps$subjectHits, "ClusterDesc"]
query[overlaps$queryHits, "ResolvedTypeMatch"] <- query[overlaps$queryHits, "ResolvedType"] == subject[overlaps$subjectHits, "ResolvedType"]
query[overlaps$queryHits, "ResolvedTypeOther"] <- subject[overlaps$subjectHits, "ResolvedType"]

query[overlaps$queryHits, "SubjectClusterCount"] <- subject[overlaps$subjectHits, "ClusterCount"]
query[overlaps$queryHits, "SubjectClusterId"] <- subject[overlaps$subjectHits, "ClusterId"]
subject[overlaps$subjectHits, "QueryClusterCount"] <- query[overlaps$queryHits, "ClusterCount"]
subject[overlaps$subjectHits, "QueryClusterId"] <- query[overlaps$queryHits, "ClusterId"]

subjectClusterCount = subject %>% select(patientId, SubjectClusterId = ClusterId, SubjectClusterCount = ClusterCount) %>% distinct()
subjectClusterCount %>% group_by(patientId, SubjectClusterId) %>% count() %>% filter(n > 1)

queryClusterMap = query %>% 
  filter(scope == 'Shared') %>% 
  select(sampleId, patientId, ClusterId, ClusterCount, SubjectClusterId) %>%
  distinct() %>%
  left_join(subjectClusterCount, by = c("patientId","SubjectClusterId")) %>%
  group_by(sampleId, ClusterId, ClusterCount) %>% 
  summarise(SubjectClusterIdCount = n(), SubjectClusterTotalCount = sum(SubjectClusterCount))

queryClusterStatus = query %>% 
  group_by(sampleId, ClusterId, ClusterCount, ResolvedType, scope) %>% 
  summarise(n = n()) %>% ungroup() %>%
  spread(scope, n, fill = 0) %>%
  left_join(queryClusterMap, by = c("sampleId", "ClusterId", "ClusterCount")) %>%
  mutate(
    SubjectClusterIdCount = ifelse(is.na(SubjectClusterIdCount), 0, SubjectClusterIdCount),
    SubjectClusterTotalCount = ifelse(is.na(SubjectClusterTotalCount), 0, SubjectClusterTotalCount)
  ) %>%
  mutate(
    status = "Mixed",
    status = ifelse(Shared == 0, "Private", status),
    status = ifelse(Private == 0 & SubjectClusterIdCount == 1 & ClusterCount == SubjectClusterTotalCount, "Exact", status),
    status = ifelse(Private > 0 & SubjectClusterIdCount == 1 & Shared == SubjectClusterTotalCount, "SimpleSuperset", status),
    status = ifelse(Private >= 0 & SubjectClusterIdCount > 1 & Shared == SubjectClusterTotalCount, "ComplexSuperset", status),
    status = ifelse(Private == 0 & SubjectClusterIdCount == 1 & ClusterCount < SubjectClusterTotalCount, "Subset", status)
  ) 

queryClusterStatusSummary = queryClusterStatus %>% group_by(ResolvedType,status) %>% count() %>% spread(status,n)
View(queryClusterStatusSummary)

jon = queryClusterStatus %>% filter(sampleId == 'CPCT02010255T')

subjectClusterMap = subject %>% 
  filter(scope == 'Shared') %>% 
  select(sampleId, ClusterId, ClusterCount, QueryClusterId) %>% 
  distinct() %>% 
  arrange(sampleId, ClusterId, ClusterCount, QueryClusterId) %>%
  group_by(sampleId, ClusterId, ClusterCount) %>% summarise(OtherClusterIdCount = n(), QueryClusterId = paste0(QueryClusterId, collapse = ",")) %>% 
  select(sampleId,  ClusterId,  OtherClusterIdCount)

queryClusterStatus = query %>% 
  group_by(sampleId,ClusterId,ClusterCount,SubjectClusterCount, ResolvedType,scope) %>% 
  count() %>% ungroup() %>%
  spread(scope, n, fill = 0) %>% mutate(SubjectClusterCount = ifelse(is.na(SubjectClusterCount), 0, SubjectClusterCount)) %>%
  left_join(queryClusterMap, by = c("sampleId", "ClusterId")) %>%
  mutate(OtherClusterIdCount = ifelse(is.na(OtherClusterIdCount), 0, OtherClusterIdCount)) %>%
  mutate(
    status = "Mixed",
    status = ifelse(Shared == 0, "Private", status),
    status = ifelse(Private == 0 & OtherClusterIdCount == 1 & ClusterCount == SubjectClusterCount, "Exact", status),
    status = ifelse(Private > 0 & OtherClusterIdCount == 1 & Shared == SubjectClusterCount, "Superset", status),
    status = ifelse(Private == 0 & OtherClusterIdCount == 1 & ClusterCount < SubjectClusterCount, "Subset", status)
  )




View(query %>% filter(scope=='Shared',ResolvedTypeMatch==F) %>% group_by(ResolvedType,scope, ResolvedTypeOther) %>% count() %>% spread(ResolvedTypeOther,n))
View(query %>% filter(scope=='Shared') %>% group_by(ResolvedType,scope, ResolvedTypeOther) %>% count() %>% spread(ResolvedTypeOther,n))
View(query %>% filter(scope=='Shared') %>% group_by(ClusterCount,scope, ClusterCountOther) %>% count() %>% spread(ClusterCountOther,n))
View(query %>% group_by(sampleId,ClusterId,ClusterCount,scope) %>% tally %>% spread(scope,n) %>% filter(!is.na(Private),!is.na(Shared)))

#private, Exact,Subset,Superset



####### DB retrieval
# I have removed the queries to get the patientId for the samples. There is a new much easier way to do it just be querying
# the sampleMapping table to get the HMFID and then stripping the last character. There are some privacy concerns you need to be aware of
# so please have a chat with me next time you need to do it and I will run you through the process.
