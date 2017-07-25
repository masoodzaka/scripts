USE hmfpatients;

	SELECT 
    count(*) as samples, 'all' as category
    FROM sample INNER JOIN patient ON sample.patientId = patient.id
    
UNION

	SELECT count(*), 'known primary tumor location' 
    FROM sample INNER JOIN patient ON sample.patientId = patient.id
    WHERE NOT(isnull(primaryTumorLocation))
    
UNION

    SELECT count(*), 'with matched biopsy' 
    FROM sample INNER JOIN patient ON sample.patientId = patient.id
    LEFT JOIN biopsy ON biopsy.sampleId = sample.sampleId
    WHERE NOT(isnull(biopsy.id))

UNION

    SELECT count(*), 'with matched biopsy and known biopsy location' 
    FROM sample INNER JOIN patient ON sample.patientId = patient.id
    LEFT JOIN biopsy ON biopsy.sampleId = sample.sampleId
    WHERE NOT(isnull(biopsy.id)) and NOT(isnull(biopsy.biopsyLocation))
    
UNION

    SELECT count(*), 'with matched biopsy and treatment' 
    FROM sample INNER JOIN patient ON sample.patientId = patient.id
    LEFT JOIN biopsy ON biopsy.sampleId = sample.sampleId
    LEFT JOIN treatment on treatment.biopsyId = biopsy.id
    WHERE NOT(isnull(treatment.id))

    

    
    
    