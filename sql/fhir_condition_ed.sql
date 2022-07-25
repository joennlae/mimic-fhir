-- Purpose: Generate a FHIR Condition resource for each row in diagnosis row in mimic-ed 
-- Methods: uuid_generate_v5 --> requires uuid or text input, some inputs cast to text to fit

DROP TABLE IF EXISTS mimic_fhir.condition_ed;
CREATE TABLE mimic_fhir.condition_ed(
    id          uuid PRIMARY KEY,
    patient_id  uuid NOT NULL,
    fhir        jsonb NOT NULL 
);

WITH fhir_condition_ed AS (
    SELECT
        TRIM(diag.icd_code) AS diag_ICD_CODE
        , diag.icd_title  AS diag_ICD_TITLE
        , diag.icd_version AS diag_ICD_VERSION
        , CASE WHEN diag.icd_version = 9 
            THEN 'http://fhir.mimic.mit.edu/CodeSystem/mimic-diagnosis-icd9' 
            ELSE 'http://fhir.mimic.mit.edu/CodeSystem/mimic-diagnosis-icd10'
        END AS diag_ICD_SYSTEM
            
  
        -- reference uuids
        , uuid_generate_v5(ns_condition.uuid, diag.stay_id || '-' || diag.seq_num || '-' || diag.icd_code) as uuid_DIAGNOSIS
        , uuid_generate_v5(ns_patient.uuid, CAST(diag.subject_id AS TEXT)) as uuid_SUBJECT_ID
        , uuid_generate_v5(ns_encounter.uuid, CAST(diag.stay_id AS TEXT)) as uuid_STAY_ID
    FROM
        mimic_ed.diagnosis diag
        LEFT JOIN fhir_etl.uuid_namespace ns_encounter 
            ON ns_encounter.name = 'EncounterED'
        LEFT JOIN fhir_etl.uuid_namespace ns_patient 
            ON ns_patient.name = 'Patient'
        LEFT JOIN fhir_etl.uuid_namespace ns_condition
            ON ns_condition.name = 'ConditionED'
)

INSERT INTO mimic_fhir.condition_ed
SELECT 
    uuid_DIAGNOSIS as id
    , uuid_SUBJECT_ID AS patient_id 
    , jsonb_strip_nulls(jsonb_build_object(
        'resourceType', 'Condition'
        , 'id', uuid_DIAGNOSIS
        , 'meta', jsonb_build_object(
            'profile', jsonb_build_array(
                'http://fhir.mimic.mit.edu/StructureDefinition/mimic-condition'
            )
        )           
        -- All diagnoses in MIMIC are considered encounter derived
        , 'category', jsonb_build_array(jsonb_build_object(
            'coding', jsonb_build_array(jsonb_build_object(
                'system', 'http://terminology.hl7.org/CodeSystem/condition-category'  
                , 'code', 'encounter-diagnosis'
            ))
        ))
        , 'code', jsonb_build_object(
            'coding', jsonb_build_array(jsonb_build_object(
                'system', diag_ICD_SYSTEM
                , 'code', diag_ICD_CODE
                , 'display', diag_ICD_TITLE
            ))
        )
        , 'subject', jsonb_build_object('reference', 'Patient/' || uuid_SUBJECT_ID)
        , 'encounter', jsonb_build_object('reference', 'Encounter/' || uuid_STAY_ID) 
    )) as fhir 
FROM
    fhir_condition_ed
LIMIT 1000
