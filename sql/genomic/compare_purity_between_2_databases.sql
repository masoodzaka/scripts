SELECT "Truth" as pipeline, version, sampleId, gender, status, qcStatus, purity, normFactor, score, somaticPenalty, ploidy, diploidProportion, polyclonalProportion, wholeGenomeDuplication, minPurity, maxPurity, minDiploidProportion, maxDiploidProportion, msIndelsPerMb, msStatus
FROM reference_validation_sets.purity WHERE sampleId = 'XXX'
UNION
SELECT "New" as pipeline, version, sampleId, gender, status, qcStatus, purity, normFactor, score, somaticPenalty, ploidy, diploidProportion, polyclonalProportion, wholeGenomeDuplication, minPurity, maxPurity, minDiploidProportion, maxDiploidProportion, msIndelsPerMb, msStatus
FROM pipeline_v5_validation.purity WHERE sampleId = 'XXX';