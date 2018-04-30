#!/usr/bin/env bash

patientId=${1}
sampleId1=${2}
sampleId2=${3}

Rscript  /data/common/repos/scripts/analysisscripts/multipleBiopsySignatures.R ${patientId} > ./multipleBiopsySignatures.log
Rscript /data/common/repos/scripts/analysisscripts/mutSignaturePerSample.R ${sampleId1} ${sampleId2} > ./mutSignaturePerSample.log