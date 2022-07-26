-- Purpose: Generate a FHIR MedicationDispense resource for each row in pyxis 
--          Add additional information from emar/emar_detail if available
-- Methods: uuid_generate_v5 --> requires uuid or text input, some inputs cast to text to fit


DROP TABLE IF EXISTS mimic_fhir.medication_dispense_ed;
CREATE TABLE mimic_fhir.medication_dispense_ed(
    id          uuid PRIMARY KEY,
    patient_id  uuid NOT NULL,
    fhir        jsonb NOT NULL 
);


WITH fhir_medication_dispense_ed AS (
    SELECT 
        py.gsn AS py_GSN
        , py.name AS py_NAME
        , CAST(py.charttime AS TIMESTAMPTZ) AS py_CHARTTIME
        
        -- reference uuids
        , uuid_generate_v5(ns_medication_dispense.uuid, py.stay_id || '-' || py.med_rn || '-' || py.gsn_rn) AS uuid_MEDICATION_DISPENSE
        , uuid_generate_v5(ns_patient.uuid, CAST(py.subject_id AS TEXT)) AS uuid_SUBJECT_ID
        , uuid_generate_v5(ns_encounter.uuid, CAST(py.stay_id AS TEXT)) AS uuid_STAY_ID
    FROM 
        mimic_ed.pyxis py  
        INNER JOIN mimic_hosp.patients pat
            ON py.subject_id = pat.subject_id
        -- UUID namespaces
        LEFT JOIN fhir_etl.uuid_namespace ns_encounter
            ON ns_encounter.name = 'EncounterED'
        LEFT JOIN fhir_etl.uuid_namespace ns_patient
            ON ns_patient.name = 'Patient'
        LEFT JOIN fhir_etl.uuid_namespace ns_medication_dispense
            ON ns_medication_dispense.name = 'MedicationDispenseED'
) 

INSERT INTO mimic_fhir.medication_dispense_ed
SELECT
    uuid_MEDICATION_DISPENSE AS id
    , uuid_SUBJECT_ID AS patient_id
    , jsonb_strip_nulls(jsonb_build_object(
        'resourceType', 'MedicationDispense'
        , 'id', uuid_MEDICATION_DISPENSE
        , 'meta', jsonb_build_object(
            'profile', jsonb_build_array(
                'http://fhir.mimic.mit.edu/StructureDefinition/mimic-medication-dispense-ed'
            )
         ) 
        , 'status', 'completed' -- assumed all complete dispense in mimic
        , 'medicationCodeableConcept', 
            CASE WHEN py_GSN IS NULL THEN
                jsonb_build_array(jsonb_build_object('text', py_NAME))
            ELSE              
                jsonb_build_array(jsonb_build_object(
                    'text', py_NAME
                    , 'coding', jsonb_build_array(jsonb_build_object(
                        'code', py_GSN
                        , 'display', py_NAME
                        , 'system', 'http://fhir.mimic.mit.edu/CodeSystem/mimic-medication-gsn'
                    ))
                ))
            END
        
        , 'subject', jsonb_build_object('reference', 'Patient/' || uuid_SUBJECT_ID)
        , 'context', jsonb_build_object('reference', 'Encounter/' || uuid_STAY_ID)
        , 'whenHandedOver', py_CHARTTIME
    )) AS fhir  
FROM 
    fhir_medication_dispense_ed;
