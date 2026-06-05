**SAP MDG Material Master**

**Setup & Configuration Guide**

Madhuri  •  SAP MDG Consultant  •  Portfolio Project  •  May 2026

# **Prerequisites**

## **System Requirements**

* SAP ECC 6.0 or S/4HANA with MDG component installed

* Minimum MDG version: 8.0

* ALE/IDOC configuration authorization

* Workflow configuration access

* ABAP development authorization

## **Access Requirements**

Transaction codes needed:

* USMD\_MODEL, USMD\_RULE, USMD\_UI\_CONF

* WE20, BD64, PFTC

Authorization objects:

* USMD\_MODIFY, S\_IDOCDEFT, PFAC

* Development key for custom ABAP

# **Implementation Roadmap**

Week 1-2: MDG Configuration  
  ├─ Data Model Setup  
  ├─ UI Configuration  
  └─ Validation Rules (BRF+)  
   
Week 3-4: IDOC Integration  
  ├─ Partner Profiles  
  ├─ Distribution Model  
  └─ IDOC Testing  
   
Week 5-6: Custom Development  
  ├─ BAdI Implementation  
  ├─ Error Monitoring Program  
  └─ Unit Testing  
   
Week 7: Integration Testing & Documentation

# **Phase 1: MDG Data Model Configuration**

## **Step 1.1 — Activate Material Data Model**

*Transaction: USMD\_MODEL*

1. Navigate to USMD\_MODEL

2. Select data model: MATERIAL

3. Click Edit, then go to the Entity Types tab

4. Ensure the following entities are active:

   * MATERIAL (Main)

   * MARA (General Data)

   * MAKT (Descriptions)

   * MARC (Plant Data)

   * MBEW (Valuation)

   * MEAN (EAN/UPC)

5. Click Check → Activate

Verification: Data model status \= Active, all required entities visible in dropdown.

## **Step 1.2 — Configure Change Request Types**

*Transaction: USMD\_CREQUEST\_TYPE or USMDCRTP*

**MAT01 — Create Material**

**CR Type:** MAT01

**Description:** Create Material

**Data Model:** MATERIAL

**Step Type:** Single-Step

**Activation:** With Workflow

**Allow Draft:** Yes

**MAT02 — Change Material**

**CR Type:** MAT02

**Description:** Change Material

**Data Model:** MATERIAL

**Step Type:** Single-Step

**Activation:** With Workflow

**Allow Draft:** Yes

**MAT03 — Extend Material to Plant**

**CR Type:** MAT03

**Description:** Extend Material to Plant

**Data Model:** MATERIAL

**Step Type:** Single-Step

**Activation:** With Workflow

**Allow Draft:** Yes

## **Step 1.3 — Configure UI**

*Transaction: USMD\_UI\_CONF*

General Data Tab — key field configuration:

| Field | Display | Mandatory | Read-Only |
| :---- | :---- | :---- | :---- |
| MATNR | Yes | Yes | No |
| MAKTX | Yes | Yes | No |
| MTART | Yes | Yes | No |
| MEINS | Yes | Yes | No |
| MATKL | Yes | Yes | No |
| BISMT | Yes | No | No |

Field Groups to create:

* Basic Data: MATNR, MAKTX, MTART, MEINS

* Classification: MATKL, BISMT

* Plant MRP: DISMM, DISPO, DISLS, EISBE

# **Phase 2: Validation Rules (BRF+)**

## **Step 2.1 — Duplicate Description Check**

*Transaction: BRF+ or USMD\_RULE*

6. Go to USMD\_RULE and create new rule:

**Rule Name:** DUPLICATE\_MAKTX\_CHECK

**Description:** Check for duplicate material description

**Rule Type:** Validation Rule

Rule logic:

IF COUNT(MAKT-MAKTX) WHERE MAKTX \= CURRENT\_MAKTX \> 0  
THEN  
  MESSAGE-TYPE \= 'E'  
  MESSAGE-TEXT \= 'Material description already exists'  
ENDIF

7. Assign rule to CR Types: MAT01, MAT02, MAT03

## **Step 2.2 — Mandatory Fields Validation**

**Rule Name:** MANDATORY\_FIELDS\_CHECK

**Description:** Check mandatory fields before activation

Rule logic:

IF MAKTX IS INITIAL  
  THEN ERROR 'Description is mandatory'  
   
IF MEINS IS INITIAL  
  THEN ERROR 'Base UOM is mandatory'  
   
IF MTART IS INITIAL  
  THEN ERROR 'Material Type is mandatory'

# **Phase 3: Workflow Configuration**

## **Step 3.1 — Configure Workflow Template**

*Transaction: PFTC*

8. Copy standard workflow WS99000076

9. Create custom workflow: Z\_WS\_MDG\_APPROVAL

**Task:** Z\_APPROVE\_MATERIAL

**Agent:** Position → Material Manager

**Deadline:** 2 days

**Escalation:** Send to supervisor after deadline

**Email Template:** Enable email notifications

## **Step 3.2 — Link Workflow to CR Types**

*Transaction: USMD\_RULE → Process Modeling*

For each CR Type (MAT01, MAT02, MAT03):

**Event:** Start of Change Request

**Action:** Start Workflow

**Workflow:** Z\_WS\_MDG\_APPROVAL

# **Phase 4: IDOC Configuration**

## **Step 4.1 — Define Logical Systems**

*Transaction: SALE → Basic Settings → Logical Systems*

| Logical System | Description |
| :---- | :---- |
| MDGHUB\_100 | MDG Central Hub |
| PLANT1\_100 | Plant 1 System |
| PLANT2\_100 | Plant 2 System |
| PLANT3\_100 | Plant 3 System |

Assign logical systems to clients via SCC4.

## **Step 4.2 — Create RFC Destinations**

*Transaction: SM59*

Example configuration for Plant 1 (repeat for Plant 2 and 3):

**RFC Destination:** SAPPLANT1

**Connection Type:** 3 (ABAP)

**Target Host:** plant1.company.com

**System Number:** 00

**Client:** 100

After saving, click Connection Test and Remote Logon to verify.

## **Step 4.3 — Configure Ports**

*Transaction: WE21*

Create tRFC port for each plant:

**Port:** SAPPLANT1

**Description:** tRFC Port to Plant 1

**RFC Destination:** SAPPLANT1

Repeat for SAPPLANT2 and SAPPLANT3.

## **Step 4.4 — Configure Partner Profiles**

*Transaction: WE20*

**Outbound Parameters (MDG Hub)**

For Partner PLANT1\_100 (type LS):

**Message Type:** MATMAS

**Receiver Port:** SAPPLANT1

**Pack Size:** 1

**Output Mode:** Transfer IDocs Immediately

**Basic Type:** MATMAS05

Repeat for PLANT2\_100 and PLANT3\_100.

**Inbound Parameters (Plant Systems)**

On each plant system, for partner MDGHUB\_100 (type LS):

**Message Type:** MATMAS

**Process Code:** MATM

**Processing Type:** Trigger Immediately

## **Step 4.5 — Create Distribution Model**

*Transaction: BD64*

10. Create new model: Z\_MDG\_MATMAS\_DIST

11. Add model view with Sender: MDGHUB\_100

12. Add receivers with plant-specific filters:

Plant 1 filter:

Message Type: MATMAS  
Filter Object: MARC  
Filter: WERKS \= 1000

Plant 2 filter:

Message Type: MATMAS  
Filter Object: MARC  
Filter: WERKS \= 2000

Plant 3 filter:

Message Type: MATMAS  
Filter Object: MARC  
Filter: WERKS \= 3000

13. Generate partner profiles: Environment → Generate Partner Profiles

# **Phase 5: Custom Development**

## **Step 5.1 — Material Validation BAdI**

*Transaction: SE19 | Enhancement Spot: USMD\_CUSTOMER*

14. Create implementation: Z\_USMD\_MATL\_IMPL

15. Add BAdI: USMD\_RULE\_SERVICE\_BADI\_MATL

16. Implementing class: ZCL\_USMD\_MATL\_VALIDATION

17. Copy code from zcl\_usmd\_matl\_validation.abap and activate

Verification: Go to SE18, confirm BAdI implementation is active. Test with a dummy change request.

## **Step 5.2 — IDOC Filter BAdI**

*BAdI: USMD\_IDOC\_FILTER*

18. Create implementation: Z\_USMD\_IDOC\_FILTER\_IMPL

19. Implementing class: ZCL\_USMD\_IDOC\_FILTER

20. Copy code from zcl\_usmd\_idoc\_filter.abap and activate

This BAdI strips non-relevant plant segments from each outbound IDOC before distribution. Critical to prevent cross-plant data leakage.

## **Step 5.3 — Error Monitoring Program**

*Transaction: SE38*

21. Create program: Z\_MDG\_IDOC\_ERROR\_MONITOR

22. Copy code from z\_mdg\_idoc\_error\_monitor.abap and activate

23. Create transaction code: ZIDOCMON

24. Schedule as background job via SM36:

    * Job Name: Z\_MDG\_IDOC\_MONITOR\_HOURLY

    * Frequency: Hourly

    * Create variant with default parameters

# **Phase 6: Testing**

## **Step 6.1 — Unit Testing**

**Validation Rules**

* Create material with duplicate description → expect error

* Create material without mandatory fields → expect error

* Enter invalid plant code → expect error

**Workflow**

* Create change request → verify workflow triggered in SWIA

* Confirm email notification sent to approver

* Approve and reject → verify status change in MDG

## **Step 6.2 — Integration Testing**

**IDOC Generation**

25. Create material with plant data and activate change request

26. Check IDOC generated in WE02

27. Verify IDOC sent to correct plant only in WE05

**IDOC Processing in Plant System**

28. Check IDOC received in WE02 on plant system

29. Verify material created in MARA/MARC with correct data

30. Cross-check plant-specific segments are accurate

## **Step 6.3 — Error Scenario Testing**

* Simulate communication error → verify auto-retry triggered

* Create material with invalid data → verify error logged with detail

* Run Z\_MDG\_IDOC\_ERROR\_MONITOR → verify reprocessing works for status 64/68

# **Post-Implementation Notes**

## **Monitoring**

* Schedule Z\_MDG\_IDOC\_ERROR\_MONITOR (SM36) to run hourly

* Review IDOC statistics regularly in WE02/WE05

* Monitor BRF+ rule hit rates in USMD\_RULE

* Enable parallel IDOC processing via RBDMOIND for high-volume scenarios

* Archive processed IDOCs after 90 days to keep EDIDC/EDID4 lean

## **Known Limitations & Planned Improvements**

* Plant-to-logical-system mapping is currently hardcoded in ZCL\_USMD\_IDOC\_FILTER — recommend moving to a Z-table for maintainability without transports

* Mandatory field list in ZCL\_USMD\_MATL\_VALIDATION is hardcoded — a configuration table would let business users adjust without developer involvement

* Current workflow is single-step for all material types — multi-level approval by material type is a planned enhancement

# **Troubleshooting Guide**

## **IDOC Not Generated**

*Symptoms: Activation successful but no IDOC created*

Checks:

* NACE configuration for output type

* Distribution model in BD64

* Partner profile in WE20

* Application log in SLG1

Use WE19 (IDOC Test Tool) to create a test IDOC manually and identify the exact failure point.

## **IDOC Status 51 — Application Error**

*Meaning: Data issue in the receiving system. Cannot be auto-reprocessed.*

31. Check error detail in WE02

32. Review data (missing mandatory fields, invalid values)

33. Correct data in MDG and reactivate the change request

## **IDOC Status 64 / 68 — Technical Error**

*Meaning: Infrastructure or connectivity issue. Safe to auto-reprocess.*

34. Run Z\_MDG\_IDOC\_ERROR\_MONITOR with reprocess checkbox enabled

35. IDOCs will be reprocessed via EDI\_DOCUMENT\_REPROCESS\_DIRECT

36. If error persists, check RFC destination and system availability

## **Validation Not Triggering**

*Symptoms: Duplicate materials being created despite BRF+ rule*

Checks:

* BAdI is active in SE19

* Rule is assigned to correct CR types in USMD\_RULE

* CR type configuration is correct

Debug: Set breakpoint in ZCL\_USMD\_MATL\_VALIDATION → CHECK\_ENTITY method, then create a test change request to confirm the BAdI is being called.

# **Transaction Code Reference**

| TCode | Description |
| :---- | :---- |
| USMD\_MODEL | Data model configuration |
| USMD\_RULE | Rule and workflow configuration |
| USMD\_UI\_CONF | UI configuration |
| MDG\_MM\_MANAGE | Material management UI |
| WE20 | Partner profiles |
| WE81 | Message types |
| BD64 | Distribution model |
| WE02 | IDOC display |
| WE05 | IDOC lists |
| WE19 | IDOC test tool |
| PFTC | Workflow definition |
| SM36 | Background job scheduling |
| SLG1 | Application log |
| SCOT | Email/SMTP configuration |

