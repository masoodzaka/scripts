library(tidyr)
library(dplyr)
library(cowplot)
library(ggplot2)
library(stringr)

localPath = '~/hmf/analyses/SVAnalysis/'
sharedPath = '~/Dropbox/HMF Australia team folder/RData/'
mySize=5
mytheme<-theme(plot.title = element_text(size=mySize),axis.text.x = element_text(angle = 90,size=mySize),axis.title.x=element_blank(),
               axis.text.y = element_text(angle = 90,size=mySize),axis.title.y = element_text(size=mySize),
               panel.grid.major.y=element_line(linetype = 5,size=0.5))

##### LOAD DATA ##### 
load(paste0(sharedPath,"highestPurityCohort.RData"))
svDrivers = read.csv(file = paste0(localPath,"LNX_DRIVERS.csv"))
svGermline = read.csv(paste(localPath,'SVGermline.csv',sep=''), header = T, stringsAsFactors = F)
svAllDrivers=read.csv(paste(localPath,'SVAllDrivers.csv',sep=''), header = T, stringsAsFactors = F)
svAllDrivers=rbind(svAllDrivers %>% select(Gene=gene,SampleId=sampleId,DriverType=driver,DriverLikelihood=driverLikelihood) %>% filter(DriverLikelihood>0.8), svGermline %>% mutate(DriverLikelihood=1,DriverType=ifelse(biallelic==1,'Germline Biallleic','Germline Monoallelic')) %>% select(Gene=gene,SampleId=sampleId,DriverType,DriverLikelihood))
driverSignatureCoocurrence = read.csv('~/Dropbox/HMF Australia team folder/SVCohortAnalysis/sv_driver_gene_cooccurence_paper_hpc.csv') 
svData = read.csv(file = paste0(localPath,"LNX_SVS.csv"))
svCluster = read.csv(file = paste0(localPath,"LNX_CLUSTERS.csv"))
svEnriched = left_join(svData,svCluster %>% separate('Annotations',c('SynLength1','SynLength2','SynGapLength'),sep=';') %>% 
  select(SampleId, ClusterId, SuperType,SynLength1,SynLength2,SynGapLength), by = c("SampleId", "ClusterId")) %>%
  filter(SuperType != 'ARTIFACT') %>% 
  mutate(IsFragile = FSStart == 'true'|FSEnd == 'true',
  IsLineElement = LEStart != 'false'| LEEnd !='false',
  IsFoldback = Type == 'INV' & FoldbackLnkStart > 0, 
  Length = PosEnd - PosStart + 1,
  HomLength = pmin(10,nchar(as.character(HomologyStart)))) %>%
  left_join(highestPurityCohort %>% select(SampleId = sampleId, CancerType = cancerType), by = "SampleId")

beData = rbind(svEnriched %>% mutate(CN=CNStart,CNChg=CNChgStart,Arm=ArmStart,LnkLen=LnkLenStart,LocTopTI=LocTopTIStart,LocTopType=LocTopTypeStart,LocTopId=LocTopIdStart,Chr=ChrStart,Pos=PosStart,Orient=OrientStart,IsStart=T,Anchor=AnchorStart,
                                 RefContext=RefContextStart,LE=LEStart,DBLength = DBLenStart,Assembled = ifelse(grepl('asm',AsmbStart),"Assembled","NotAssembled")),
               svEnriched %>% mutate(CN=CNEnd,CNChg=CNChgEnd,Arm=ArmEnd,LnkLen=LnkLenEnd,LocTopTI=LocTopTIEnd,LocTopType=LocTopTypeEnd,LocTopId=LocTopIdEnd,Chr=ChrEnd,Pos=PosEnd,Orient=OrientEnd,IsStart=F,Anchor=AnchorEnd,
                                 RefContext=RefContextEnd,LE=LEEnd,DBLength = DBLenEnd, Assembled = ifelse(grepl('asm',AsmbStart),"Assembled","NotAssembled"))) %>%
  select(SampleId,Id,IsStart,CN,CNChg,ClusterId,CancerType,Type,ResolvedType,Arm,LnkLen,LocTopTI,LocTopType,LocTopId,Chr,Pos,Orient,RefContext,LE,DBLength,Assembled,Anchor,IsPolyA,ClusterCount,PloidyMin,PloidyMax,ClusterCountBucket,ClusterDesc,Synthetic,LengthBucket,IsFoldBack) %>% 
  mutate(DBLenBucket = ifelse(DBLength==0,0,ifelse(DBLength<0,-(2**round(log(-DBLength,2))),2**round(log(DBLength,2)))))
load('~/Documents/recurrentIndelSummary.RData')

# Samples with key drivers
sample_filter_by_driver<-function(driverGene){
  return((svAllDrivers %>% filter(DriverLikelihood>0.8,Gene == driverGene) %>% .$SampleId))
}
CDK12samples=sample_filter_by_driver('CDK12')
CCNE1samples=sample_filter_by_driver('CCNE1')
BRCA2samples=sample_filter_by_driver('BRCA2')
BRCA1samples=sample_filter_by_driver('BRCA1')
PALB2samples=sample_filter_by_driver('PALB2')
TP53samples=sample_filter_by_driver('TP53')
######################### 

##### FUNCTIONS ######
plot_eight_violins <- function(svEnriched,complexType = 'COMPLEX',violinScale = 'area') {
  
  svSimple = svEnriched %>% filter(!IsFoldback, Type %in% c("DUP","DEL", "INV"), ClusterCount == 1|ResolvedType=='SIMPLE_GRP') %>% mutate(Feature = paste0(Type," - Simple")) %>% select(Feature, Length)
  svComplex = svEnriched %>% filter(!IsFoldback, Type %in% c("DUP","DEL", "INV"), ResolvedType == complexType) %>% mutate(Feature = paste0(Type," - ",complexType)) %>% select(Feature, Length)
  svRecipInv = svEnriched %>% filter(!IsFoldback, grepl('RECIP_INV',ResolvedType),ClusterCount==2) %>% mutate(Feature = 'INV - Reciprocal') %>% select(Feature, Length)
  #svRecipInv = svEnriched %>% filter(!IsFoldback, grepl('RECIP_INV',ResolvedType)) %>% mutate(Feature = ResolvedType, Length = pmax(PosEnd, PosStart) - pmin(PosEnd, PosStart) + 1) %>% select(Feature, Length)
  
  fbStart = svEnriched %>% filter(FoldbackLenStart>=0) %>% select(SampleId,Id,ClusterId,Chr=ChrStart,Arm=ArmStart,FoldbackLength=FoldbackLenStart,OtherId=FoldbackLnkStart)
  fbEnd = svEnriched %>% filter(FoldbackLenEnd>=0) %>% select(SampleId,Id,ClusterId,Chr=ChrEnd,Arm=ArmEnd,FoldbackLength=FoldbackLenEnd,OtherId=FoldbackLnkEnd)
  svFoldbacks = rbind(fbStart,fbEnd) %>% mutate(Feature='Foldback',Length = FoldbackLength+1) %>% select(Feature,Length)  #+1 allows dsiplay of 0 length
  
  svComplete = bind_rows(svSimple,svRecipInv) %>% bind_rows(svComplex) %>% bind_rows(svFoldbacks) 
  svFeatureLevels = unique(svComplete$Feature)
  svComplete = svComplete %>% mutate(Feature = factor(Feature, svFeatureLevels))
  
  ggplot(svComplete, aes(Feature, Length)) + 
    geom_violin(scale = violinScale,fill='light blue',color=NA) + 
    scale_y_log10() + mytheme
}
plot_simple_dels_recip_inv <- function(svEnriched,violinScale = 'area') {
  
  svSimple = svEnriched %>% filter(!IsFoldback, Type %in% c("DEL"), ClusterCount == 1) %>% mutate(Feature = paste0(Type," - Simple")) %>% select(Feature, Length)
  svRecipInv = svEnriched %>% filter(!IsFoldback, ResolvedType == "RECIP_INV") %>% mutate(Feature = "INV - Reciprocal", Length = pmax(PosEnd, PosStart) - pmin(PosEnd, PosStart) + 1) %>% select(Feature, Length)
  svComplete = bind_rows(svSimple,svRecipInv) 
  svFeatureLevels = unique(svComplete$Feature)
  svComplete = svComplete %>% mutate(Feature = factor(Feature, svFeatureLevels))
  
  ggplot(svComplete, aes(Feature, Length)) + 
    geom_violin(scale = violinScale,fill='light blue',color=NA) + 
    scale_y_log10() + mytheme
}
create_violin_plot_cancer_type <- function(x,feature='Length',scaleLogY=T,violinScale = 'area') {
  
  cancerTypeCounts = highestPurityCohort %>% group_by(cancerType) %>% count() %>% arrange(-n) %>%  ungroup()  %>% 
    mutate(CancerType = cancerType, weight = 1.0/n,Label = paste0(CancerType," (n=", n,")")) %>% select(CancerType, weight,Label)
  plotDF = x %>%
    filter(!is.na(CancerType)) %>%
    left_join(cancerTypeCounts, by = "CancerType") %>%
    mutate(Label = factor(Label, cancerTypeCounts$Label, ordered = T))
  
  p1 = ggplot(plotDF, aes_string('Label', feature)) + 
    geom_violin(scale = violinScale, aes(weight = weight),fill='light blue',color=NA)+mytheme
    
  
  if (scaleLogY==T) {
    p1 = p1+ scale_y_log10(breaks = scales::trans_breaks("log10", function(x) 10^x))
  }
  return (p1)
}
create_top_n_violin_plot <- function(x, topN=40,minVariants = 0,feature='Length',scaleLogY=T) {
  xSummary = x %>% group_by(SampleId) %>% 
    count() %>% 
    filter(n > minVariants) %>%
    arrange(-n) %>% 
    ungroup() %>% 
    top_n(topN, n) %>%
    left_join(highestPurityCohort %>% select(SampleId = sampleId, CancerType = cancerType), by = "SampleId") %>%
    arrange(CancerType, -n) %>% 
    mutate(Label = str_wrap(paste0(SampleId,' ', ifelse(is.na(CancerType),"Unknown",CancerType),"(n=", n,")"),16)) %>% select(SampleId, Label)
  
  plotDF = x %>% filter(SampleId %in% xSummary$SampleId) %>% left_join(xSummary, by = "SampleId") %>% mutate(Label = factor(Label, xSummary$Label, ordered = T))
  
  p1 = ggplot(plotDF, aes_string('Label', feature)) + geom_violin(scale = 'area',fill='light blue',color=NA) +mytheme
  
  if (scaleLogY==T) {
    p1 = p1+ scale_y_log10(breaks = scales::trans_breaks("log10", function(x) 10^x))
  }
  
  return (p1)
}
plot_synthetics <- function(svEnriched,violinScale = 'area') {
  svSimple = svEnriched %>% filter(Type %in% c("DUP","DEL"), ClusterCount == 1) %>% mutate(Feature = paste0("Simple ",Type)) %>% select(Feature, Length) %>% arrange(Feature)
  synStart = svEnriched %>% filter(ClusterCount>1,ResolvedType %in% c('DEL','DUP'),is.na(LnkSvStart)) %>% select(SampleId,Id,ClusterId,Chr=ChrStart,Arm=ArmStart,Pos=PosStart,ResolvedType)
  synEnd = svEnriched %>% filter(ClusterCount>1,ResolvedType %in% c('DEL','DUP'),is.na(LnkSvEnd)) %>% select(SampleId,Id,ClusterId,Chr=ChrEnd,Arm=ArmEnd,Pos=PosEnd,ResolvedType)
  svSyn = bind_rows(synStart,synEnd) %>% 
    group_by(SampleId,ClusterId,ResolvedType) %>%
    summarise(Length=max(Pos)-min(Pos)) %>% ungroup() %>% mutate(Feature = paste0("Synthetic ",ResolvedType)) %>% select(Feature, Length) %>% arrange(Feature)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svRecipDups = bind_rows(svEnriched %>% filter(ResolvedType=='RECIP_INV_DUPS'|ResolvedType=='RECIP_TRANS_DUPS', ClusterCount == 2) %>% mutate(Length=as.numeric(SynLength1),Feature = "RECIP_DUPS") %>% select(Feature, Length) %>% arrange(Feature),
                          svEnriched %>% filter(ResolvedType=='RECIP_INV_DUPS'|ResolvedType=='RECIP_TRANS_DUPS', ClusterCount == 2) %>% mutate(Length=as.numeric(SynLength2),Feature = "RECIP_DUPS") %>% select(Feature, Length) %>% arrange(Feature))
  svRecipDups= bind_rows(svRecipDups,svRecipDups)
  svRecipDups= bind_rows(svRecipDups,svRecipDups)
  
  fbStart = svEnriched %>% filter(FoldbackLenStart>=0) %>% select(SampleId,Id,ClusterId,Chr=ChrStart,Arm=ArmStart,FoldbackLength=FoldbackLenStart,OtherId=FoldbackLnkStart)
  fbEnd = svEnriched %>% filter(FoldbackLenEnd>=0) %>% select(SampleId,Id,ClusterId,Chr=ChrEnd,Arm=ArmEnd,FoldbackLength=FoldbackLenEnd,OtherId=FoldbackLnkEnd)
  svFoldbacks = rbind(fbStart,fbEnd) %>% mutate(Feature=paste0(ifelse(Id==OtherId,'Simple',' Synthetic'),'Foldback'),Length = FoldbackLength+1) %>% select(Feature,Length)  #+1 allows dsiplay of 0 length
  
  svComplete = bind_rows(svSimple,svSyn) %>% bind_rows(svFoldbacks) 
  #svComplete=svFoldbacks
  svFeatureLevels = unique(svComplete$Feature)
  svComplete = svComplete %>% mutate(Feature = factor(Feature, svFeatureLevels))
  
  ggplot(svComplete, aes(Feature, Length)) + 
    geom_violin(scale = violinScale,fill='light blue',color=NA) + 
    scale_y_log10() + mytheme
}
plot_equivalents <- function(svEnriched,violinScale = 'area') {
  svSimple = svEnriched %>% filter(Type %in% c("DUP","DEL"), ClusterCount == 1) %>% mutate(Feature = paste0("Simple ",Type)) %>% select(Feature, Length) %>% arrange(Feature)
  synStart = svEnriched %>% filter(ClusterCount>1,ResolvedType %in% c('DEL','DUP'),is.na(LnkSvStart)) %>% select(SampleId,Id,ClusterId,Chr=ChrStart,Arm=ArmStart,Pos=PosStart,ResolvedType)
  synEnd = svEnriched %>% filter(ClusterCount>1,ResolvedType %in% c('DEL','DUP'),is.na(LnkSvEnd)) %>% select(SampleId,Id,ClusterId,Chr=ChrEnd,Arm=ArmEnd,Pos=PosEnd,ResolvedType)
  svSyn = bind_rows(synStart,synEnd) %>% 
    group_by(SampleId,ClusterId,ResolvedType) %>%
    summarise(Length=max(Pos)-min(Pos)) %>% ungroup() %>% mutate(Feature = paste0("Synthetic ",ResolvedType)) %>% select(Feature, Length) %>% arrange(Feature)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svSyn= bind_rows(svSyn,svSyn)
  svRecipDups = bind_rows(svEnriched %>% filter(ResolvedType=='RECIP_INV_DUPS'|ResolvedType=='RECIP_TRANS_DUPS', ClusterCount == 2) %>% mutate(Length=as.numeric(SynLength1),Feature = "RECIP_DUPS") %>% select(Feature, Length) %>% arrange(Feature),
                         svEnriched %>% filter(ResolvedType=='RECIP_INV_DUPS'|ResolvedType=='RECIP_TRANS_DUPS', ClusterCount == 2) %>% mutate(Length=as.numeric(SynLength2),Feature = "RECIP_DUPS") %>% select(Feature, Length) %>% arrange(Feature))
  svRecipDups= bind_rows(svRecipDups,svRecipDups)
  svRecipDups= bind_rows(svRecipDups,svRecipDups)

  svComplete = bind_rows(svSimple,svSyn) %>% bind_rows(svRecipDups)  
  svFeatureLevels = unique(svComplete$Feature)
  svComplete = svComplete %>% mutate(Feature = factor(Feature, svFeatureLevels))
  
  ggplot(svComplete, aes(Feature, Length)) + 
    geom_violin(scale = violinScale,fill='light blue',color=NA) + 
    scale_y_log10() + mytheme
}
create_violin_plot_resolved_type <- function(x,feature='Length',scaleLogY=T) {
  
  plotDF = x %>% mutate(Label = factor(ResolvedType, ordered = T)) #%>%left_join(cancerTypeCounts)
  
  p1 = ggplot(plotDF, aes_string('Label', feature)) + 
    geom_violin(bw=0.1,scale = "area",fill='light blue',color=NA) + mytheme
  
  if (scaleLogY==T) {
    p1 = p1+ scale_y_log10()
  }
  return (p1)
}
plot_count_by_bucket_and_type<-function(countsData,bucket,facetWrap,titleString ="",useLogX = TRUE,useLogY = TRUE) {
  plot <- ggplot(data=countsData,aes_string(x=bucket))+
    geom_line(aes(y=countDEL,colour='DEL'))+
    geom_line(aes(y=countDUP,colour='DUP'))+
    geom_line(aes(y=countINV,colour='INV'))+
    geom_line(aes(y=countBND,colour='BND'))+
    geom_line(aes(y=countSGL, colour='SGL'))+
    facet_wrap(as.formula(paste("~", facetWrap)))+
    labs(title = titleString) +theme_bw() + theme(panel.grid.major = element_line(colour="grey", size=0.5))
  if (useLogX == TRUE) {
    plot<-plot+scale_x_log10()
  }
  if (useLogY == TRUE) {
    plot<-plot+scale_y_log10()
  }
  print(plot)
}
cohortSummary<-function(cluster,filterString = "",groupByString = "") {
  (cluster %>% s_filter(filterString) %>% s_group_by(groupByString)
   %>% summarise(count=n(),
                 countSGL=sum(Type=='SGL'),
                 countNONE=sum(Type=='NONE'),
                 countBND=sum(Type=='BND'),
                 countINV=sum(Type=='INV'),
                 countDEL=sum(Type=='DEL'),
                 countDUP=sum(Type=='DUP'))
   %>% arrange(-count) %>% as.data.frame)
}
######################
##### LENGTH ANALYSES #######
### 1. High level INV,DEL and DUP Lengths ###
p1 = plot_eight_violins(svEnriched,'COMPLEX','count') + ggtitle("local variants by count")
p2 = plot_eight_violins(svEnriched,'COMPLEX','area') + ggtitle("local variants equal area")
p3 = plot_eight_violins(svEnriched %>% filter(IsFragile),'COMPLEX','count') + ggtitle("Fragile site only")
plot_grid(p1, p2,p3, ncol = 1)
print(p1)

##### 1.A Simple DELS vs reciprocal Inversions
plot_simple_dels_recip_inv(svEnriched,'area')
### 2. Simple DELS and DUPS  by Cancer Type ###
pCancerTypeDups = create_violin_plot_cancer_type(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1)) + ggtitle("Length Distribution: Simple DUP by CancerType (count per sample)")
pCancerTypeDels = create_violin_plot_cancer_type(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1)) + ggtitle("Simple DEL by CancerType (count per sample)")
plot_grid(pCancerTypeDups, pCancerTypeDels, ncol = 1)

### 3. Simple DELS and DUPS top 50 samples ####
#TO DO: can we colour violin by enriched driver genes?
p1 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1),40) + ggtitle("Simple Top 50 Dups",)
p2 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1) ,40) + ggtitle("Simple Top 50 Dels")
plot_grid(p1,p2, ncol = 1)

### 4.Simple DUP top N by enriched driver Gene ###
p1 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% CDK12samples)),20,minVariants = 40) + ggtitle("Length Top CDK12 Dups")
p2 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% CCNE1samples)),20,minVariants = 40) + ggtitle("Length Top CCNE1 Dups")
p3 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% BRCA1samples)),20,minVariants = 40) + ggtitle("Length Top BRCA1 Dups")
p4 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% CDK12samples)),20,feature='RepOriginStart',scaleLogY=F,minVariants = 40) + ggtitle("Rep Top CDK12 Dups")
p5 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% CCNE1samples)),20,feature='RepOriginStart',scaleLogY=F,minVariants = 40) + ggtitle("Rep Top CCNE1 Dups")
p6 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1,(SampleId %in% BRCA1samples)),20,feature='RepOriginStart',scaleLogY=F,minVariants = 40) + ggtitle("Rep Top BRCA1 Dups")
plot_grid(p1,p4,p2,p5,p3,p6, ncol = 2)
plot_grid(p3,p4,p5, ncol = 1)

### 5.Simple DEL top N by enriched driver Gene ###
p6 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1,(SampleId %in% BRCA1samples))) + ggtitle("Simple Top BRCA1 DEL")
p7 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1,(SampleId %in% BRCA2samples))) + ggtitle("Simple Top BRCA2 DEL")
p8 = create_top_n_violin_plot(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1,(SampleId %in% PALB2samples))) + ggtitle("Simple Top PALB2 DEL")
plot_grid(p6,p7,p8, ncol = 1)

### 4.Simple DUP top N for enriched cancer types ###
p10 = create_top_n_violin_plot(svEnriched %>% filter(Type=="DUP", ClusterCount == 1,CancerType=='Ovary'),20) + ggtitle("Simple top Ovary DUP")
p11 = create_top_n_violin_plot(svEnriched %>% filter(Type=="DUP", ClusterCount == 1,CancerType %in% c('Esophagus','Stomach')),20) + ggtitle("Simple Top Esophagus & Stomach DUP")
p12 = create_top_n_violin_plot(svEnriched %>% filter(Type=="DUP", ClusterCount == 1,CancerType=='Prostate'),20) + ggtitle("Simple Top Prostate DUP")
p13 = create_top_n_violin_plot(svEnriched %>% filter(Type=="DUP", ClusterCount == 1,CancerType=='Breast'),20) + ggtitle("Simple Top Breast DUP")
plot_grid(p10,p11,p12,p13, ncol = 1)

### 5. Simple vs synthetic lengths overall ###
plot_synthetics(svEnriched,'area') + ggtitle("Synthetics")

### 6. Simple vs synthetic lengths by driver gene ###
p0= plot_synthetics(svEnriched,'count') + ggtitle("All Samples")
p1=plot_synthetics(svEnriched %>% filter(SampleId %in% CDK12samples),'count') + ggtitle("Samples with  CDK12 drivers")
p2=plot_synthetics(svEnriched %>% filter(SampleId %in% CCNE1samples),'count') + ggtitle("Samples with CCNE1 drivers")
p3=plot_synthetics(svEnriched %>% filter(SampleId %in% BRCA1samples),'count') + ggtitle("Samples with BRCA1 drivers")
p4=plot_synthetics(svEnriched %>% filter(SampleId %in% BRCA2samples),'count') + ggtitle("Samples with BRCA2 drivers")
plot_grid(p0,p1,p2,p3,p4,ncol=1)

### 7. Reciprocal DUPS ###
pairClusters = svCluster %>% filter(ClusterCount==2,ResolvedType=='RECIP_TRANS_DUPS'|ResolvedType=='RECIP_INV_DUPS') %>% separate('Annotations',c('SynLength1','SynLength2','SynGapLength'),sep=';') %>% 
  mutate(SynGapLength=as.numeric(as.character(SynGapLength)),SynLength1=as.numeric(as.character(SynLength1)),SynLength2=as.numeric(as.character(SynLength2)))
p0=ggplot(data=pairClusters,aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("All") +mytheme
p1=ggplot(data=pairClusters %>% filter(SampleId %in% BRCA1samples),aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("BRCA1") +mytheme
p2=ggplot(data=pairClusters %>% filter(SampleId %in% CCNE1samples),aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("CCNE1") +mytheme
p3=ggplot(data=pairClusters %>% filter(SampleId %in% CDK12samples),aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("CDK12") +mytheme
plot_grid(p0,p1,p2,p3,ncol=1)


### 7. Reciprocal INV ###
pairClusters = svCluster %>% filter(ClusterCount==2,ResolvedType=='RECIP_TRANS_DEL_DUP'|ResolvedType=='RECIP_INV_DEL_DUP') %>% separate('Annotations',c('SynLength1','SynLength2','SynGapLength'),sep=';') %>% 
  mutate(SynGapLength=as.numeric(as.character(SynGapLength)),SynLength1=as.numeric(as.character(SynLength1)),SynLength2=as.numeric(as.character(SynLength2)))
p0=ggplot(data=pairClusters,aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("All") +mytheme
p1=ggplot(data=pairClusters %>% filter(SampleId %in% BRCA1samples),aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("BRCA1") +mytheme
p2=ggplot(data=pairClusters %>% filter(SampleId %in% CCNE1samples),aes(SynLength1,SynLength2)) + geom_hex(bins=30) + facet_wrap(~ResolvedType) + scale_x_log10() + scale_y_log10()+
  scale_fill_gradient(low = 'light blue', high = 'dark blue') + ggtitle("BRCA2") +mytheme
plot_grid(p0,p1,p2,ncol=1)

################################

##### Variant Counts  #######
#1. By cancer Type and Resolved Type
topResolvedTypes = svEnriched  %>% filter(SuperType!='INCOMPLETE') %>% group_by(ResolvedType) %>% count %>% filter(n>2500) %>% .$ResolvedType
allCounts = svEnriched  %>% group_by(SampleId,CancerType,ResolvedType) %>% summarise(count=n()) %>% tidyr::complete(SampleId,CancerType,ResolvedType,fill=list(count=0.5))
create_violin_plot_cancer_type(allCounts %>% filter(ResolvedType %in% topResolvedTypes) ,'count',T) +  ggtitle("Counts of Variants by Resolved Type") + facet_wrap(~ResolvedType)
#create_violin_plot_cancer_type(allCounts %>% filter(ResolvedType=='RECIP_TRANS') ,'count',T,'area') +  ggtitle("Counts of Variants by Resolved Type") + facet_wrap(~ResolvedType)


#2. Telomeric SGL

TelomericSGL = merge(svEnriched  %>% filter(Type=='SGL',RepeatType %in% c('(CCCTAA)n','(TTAGGG)n'))%>% group_by(SampleId,CancerType) %>% summarise(count=n()),
    highestPurityCohort %>% select(SampleId=sampleId,CancerType=cancerType),by=c('SampleId','CancerType'),all=T) %>% mutate(count=ifelse(is.na(count),0.1,count))

create_violin_plot_cancer_type(TelomericSGL,'count',scaleLogY = T,violinScale = 'width') +  ggtitle("Counts of Telomoric SGL") 

View(merge(TelomericSGL,svAllDrivers %>% filter(Gene=='ATRX') %>% select(SampleId,Gene),by='SampleId',all.x=T))
ggplot(merge(TelomericSGL,svAllDrivers %>% filter(Gene=='ATRX') %>% select(SampleId,Gene),by='SampleId',all.x=T) %>% mutate(Has_ATRX_Driver=factor(Gene)), aes(Has_ATRX_Driver, count)) + 
    geom_violin(scale = 'area',fill='light blue',color=NA) +  ggtitle("Counts of Telomeric SGL per sample") + scale_y_log10()

#create_violin_plot_cancer_type(allCounts %>% filter(ResolvedType=='RECIP_TRANS') ,'count',T,'area') +  ggtitle("Counts of Variants by Resolved Type") + facet_wrap(~ResolvedType)
################################

##### DB LENGTH ANALYSES #######
### 1. Short DB lengths by Resolved Type ###
#TODO: switch to breakend based
plot_count_by_bucket_and_type(cohortSummary(beData, "DBLength<=50,DBLength>=-50,Subclonal!='false',ResolvedType %in% c('COMPLEX','LINE','RECIP_INV','RECIP_TRANS'),ClusterCount>=2",'DBLength,ResolvedType'),
                              'DBLength','ResolvedType','DB Length for selected resolved types(<=100bases)',useLogX = F,useLogY = T)

################################

##### HOM LENGTH ANALYSES ######
### 1. HOM engths by Resolved Type ###
# TODO: convert to bar chart.  
# LINE has least homology, followed by COMPLEX and RECIP events.  PAIR_OTHER has a very long upper tail.  DELS and DUPS have nuances by length
View(svEnriched %>% filter(SuperType!='INCOMPLETE',Type!='SGL',Type!='INF') %>% group_by(ResolvedType,HL=pmin(20,nchar(as.character(Homology)))) %>% count %>% spread(HL,n))

################################

############ VIRAL INSERTIONS ###############
#1. all samples
svVirus = svEnriched %>% filter(VirusName!='') %>% 
             mutate(VirusType=ifelse(grepl('HBV',VirusName)|grepl('Hepatitis',VirusName),'HBV',
                              ifelse(grepl('papillomavirus',VirusName),'HPV',
                              ifelse(grepl('Merkel',VirusName),'Merkel Cell',
                              ifelse(grepl('herpesvirus',VirusName),'herpesvirus',
                              ifelse(grepl('Adeno',VirusName),'AAV','other'))))))
         
View(svVirus %>% group_by(CancerType,SampleId,VirusName,VirusType) %>% count())

#2. by cancer type
View(svVirus %>% group_by(CancerType,SampleId,VirusType) %>% count() %>% 
       group_by(CancerType,VirusType) %>% count() %>% spread(VirusType,nn))

################################


View(driverSignatureCoocurrence %>% arrange(FDR) %>% 
       filter(FDR<0.05,CancerType!='All',CountGtExp!='false',grepl('DEL',Category)) %>% 
       group_by(Gene,Category,CancerType) %>% summarise(q=sum(FDR)) %>% spread(CancerType,q,fill=''))
View(driverSignatureCoocurrence %>% arrange(FDR) %>% 
       filter(FDR<0.05,CancerType!='All',CountGtExp!='false',grepl('DUP',Category)) %>% 
       group_by(Gene,Category,CancerType) %>% summarise(q=sum(FDR)) %>% spread(CancerType,q,fill=''))

View(driverSignatureCoocurrence %>% arrange(FDR) %>% 
       filter(FDR<0.05,CancerType!='All',CountGtExp!='false',grepl('LINE',Category)) %>% 
       group_by(Gene,Category,CancerType) %>% summarise(q=sum(FDR)) %>% spread(CancerType,q,fill=''))

########## SCRATCH##############
# 4 main genes are almost mutually exclusive
View(svAllDrivers %>% filter(Gene %in% c('CDK12','BRCA1','BRCA2','CCNE1')) %>% group_by(Gene,SampleId) %>% count %>% spread(Gene,n))

p1 = ggplot(plotDF, aes_string('Label','SampleId')) + 
  geom_violin(scale = "area", aes(weight = weight),fill='light blue',color=NA)  +theme(axis.text.x = element_text(angle = 90)) +
  theme(axis.text.x = element_text(angle = 90,size=8),axis.title.x=element_blank(),
        axis.text.y = element_text(angle = 90,size=8),axis.title.y = element_text(size=8),
        panel.grid.major.y=element_line(linetype = 8,size=0.1))
print(p1)

View(svEnriched  %>% filter(Type %in% c("INV"), ClusterCount == 2,ResolvedType=='RECIP_INV') %>% group_by(SampleId,CancerType,long=Length<2e5) %>% count %>% spread(long,n))

pCancerTypeDups = create_violin_plot_cancer_type(svEnriched %>% filter(Type %in% c("DUP"), ClusterCount == 1),feature='RepOriginStart',scaleLogY = F,violinScale = 'width') + ggtitle("Length Distribution: Simple DUP by CancerType (count per sample)")
pCancerTypeDels = create_violin_plot_cancer_type(svEnriched %>% filter(Type %in% c("DEL"), ClusterCount == 1),feature='RepOriginStart',scaleLogY = F,violinScale = 'width') + ggtitle("Simple DEL by CancerType (count per sample)")
plot_grid(pCancerTypeDups, pCancerTypeDels, ncol = 1)

create_top_n_violin_plot(svEnriched %>% filter(Type=='DUP'),50,feature='RepOriginStart',scaleLogY=F,minVariants = 10) + ggtitle("Rep Top CDK12 Dups")
head(svEnriched)
x=svEnriched %>% filter(Type=="DUP", ClusterCount == 1,CancerType=='Ovary')

