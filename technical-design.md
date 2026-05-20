# Technical Design Document: SAP MDG Material Master with IDOC Distribution

## Document Information

**Project**: Material Master MDG with IDOC Integration  
**Version**: 1.0  
**Author**: Madhuri - SAP MDG Consultant  


---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [MDG Configuration](#mdg-configuration)
3. [IDOC Integration Design](#idoc-integration-design)
4. [Custom Developments](#custom-developments)
5. [Workflow Configuration](#workflow-configuration)
6. [Error Handling Strategy](#error-handling-strategy)
7. [Performance Considerations](#performance-considerations)

---

## Architecture Overview

### System Landscape

```
┌─────────────────────────────────────────────────────────────┐
│                    MDG Central Hub                          │
│                 (SAP ECC 6.0 + MDG 8.0)                    │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              MDG Material Object                      │  │
│  │  - Data Model: MATERIAL                              │  │
│  │  - Edition: MDG 8.0                                  │  │
│  │  - UI Type: NWBC / WebDynpro                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Validation Layer (BRF+)                     │  │
│  │  - Duplicate Check                                   │  │
│  │  - Mandatory Field Validation                        │  │
│  │  - Material Type-Specific Rules                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │        Workflow Engine (SAP Business Workflow)        │  │
│  │  - Template: USMD_ATC_1ST                            │  │
│  │  - Approval Step: Material Manager                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │            Activation & Replication                   │  │
│  │  - Activation Program: USMD_ACTIVATE                 │  │
│  │  - Outbound Processing: RBDMIDOC                     │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              IDOC Generation                          │  │
│  │  - Message Type: MATMAS                              │  │
│  │  - IDOC Type: MATMAS05                              │  │
│  │  - Process Code: MATM (Inbound)                     │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
              ▼           ▼           ▼
      ┌──────────┐ ┌──────────┐ ┌──────────┐
      │ Plant 1  │ │ Plant 2  │ │ Plant 3  │
      │ (1000)   │ │ (2000)   │ │ (3000)   │
      │ RFC:     │ │ RFC:     │ │ RFC:     │
      │ CLNT100  │ │ CLNT200  │ │ CLNT300  │
      └──────────┘ └──────────┘ └──────────┘
```

### Integration Pattern

**Method**: Asynchronous IDOC Distribution via ALE  
**Trigger**: Post-activation event in MDG  
**Frequency**: Real-time (immediate processing)  
**Direction**: Hub → Spoke (Unidirectional)

---

## MDG Configuration

### Data Model Setup

**Transaction**: USMD_MODEL

```
Data Model: MATERIAL
└── Entity Types:
    ├── MATERIAL (Main Entity)
    │   ├── Attributes:
    │   │   ├── MATNR (Material Number) - Key
    │   │   ├── MAKTX (Description)
    │   │   ├── MEINS (Base UOM)
    │   │   ├── MTART (Material Type)
    │   │   └── MATKL (Material Group)
    │   │
    ├── MARA (General Material Data)
    ├── MAKT (Material Descriptions)
    ├── MARC (Plant Data)
    ├── MARD (Storage Location Data)
    ├── MBEW (Valuation Data)
    └── MEAN (EAN/UPC)
```

### Change Request Types

**Transaction**: USMDCRTP

| CR Type | Description | Activation Method |
|---------|-------------|-------------------|
| MAT01 | Create Material | Single Step Activation |
| MAT02 | Change Material | Single Step Activation |
| MAT03 | Extend Material to Plant | Single Step Activation |
| MAT04 | Block/Unblock Material | Direct Activation |

### UI Configuration

**Transaction**: USMD_UI_CONF

**Main Screen Tabs**:
1. General Data (MARA fields)
2. Descriptions (MAKT - Multi-language support)
3. Plant Data (MARC - per plant)
4. Storage Location (MARD)
5. Accounting (MBEW)
6. Purchasing (EINA/EINE)

**Field Properties**:
```
MAKTX (Description):
  - Read-Only: No
  - Mandatory: Yes
  - Check: Duplicate description check (BRF+)

MEINS (Base UOM):
  - Read-Only: No
  - Mandatory: Yes
  - Value Help: T006 (UOM table)

WERKS (Plant):
  - Read-Only: No
  - Mandatory: Yes (for plant data)
  - Value Help: T001W (Plant table)
```

---

## IDOC Integration Design

### Message Type Configuration

**Transaction**: WE81

```
Message Type: MATMAS
Description: Material Master Distribution
Direction: Outbound
Basic Type: MATMAS05
```

### IDOC Type Structure (MATMAS05)

```
MATMAS05
├── E1MARAM (Control Segment)
│   └── Material Header Data
│       ├── MATNR (Material Number)
│       ├── MTART (Material Type)
│       └── MEINS (Base UOM)
│
├── E1MAKTM (Material Description)
│   ├── MAKTX (Description)
│   └── SPRAS (Language)
│
├── E1MARCM (Plant Data)
│   ├── WERKS (Plant)
│   ├── DISMM (MRP Type)
│   ├── DISPO (MRP Controller)
│   └── EISBE (Safety Stock)
│
├── E1MBEWM (Valuation Data)
│   ├── BWKEY (Valuation Area)
│   ├── VPRSV (Price Control)
│   └── STPRS (Standard Price)
│
└── E1MEANM (EAN/UPC)
    └── EAN11 (EAN Number)
```

### Partner Profile Configuration

**Transaction**: WE20

**Logical System Setup**:

| Logical System | Description | Physical System |
|---------------|-------------|-----------------|
| MDGHUB_100 | MDG Central Hub | MDG Production |
| PLANT1_100 | Plant 1 System | ECC Plant 1 |
| PLANT2_100 | Plant 2 System | ECC Plant 2 |
| PLANT3_100 | Plant 3 System | ECC Plant 3 |

**Outbound Parameters (MDG Hub)**:

```
Partner Profile: PLANT1_100 (LS Type)
├── Outbound Parameters
│   ├── Message Type: MATMAS
│   ├── Receiver Port: SAPPLANT1 (RFC)
│   ├── Output Mode: Transfer IDocs Immediately
│   ├── Basic Type: MATMAS05
│   └── Process Code: (Blank - determined by receiver)
```

**Inbound Parameters (Plant Systems)**:

```
Partner Profile: MDGHUB_100 (LS Type)
├── Inbound Parameters
│   ├── Message Type: MATMAS
│   ├── Process Code: MATM
│   ├── Processing by Function: Trigger Immediately
│   └── Function Module: IDOC_INPUT_MATMAS
```

### Distribution Model

**Transaction**: BD64

```
Distribution Model: Z_MDG_MATMAS_DIST
└── Model View: Material Master Distribution
    ├── Sender: MDGHUB_100
    └── Receivers:
        ├── PLANT1_100
        │   └── Message Type: MATMAS
        │       └── Filter: Plant = 1000
        │
        ├── PLANT2_100
        │   └── Message Type: MATMAS
        │       └── Filter: Plant = 2000
        │
        └── PLANT3_100
            └── Message Type: MATMAS
                └── Filter: Plant = 3000
```

---

## Custom Developments

### 1. Validation BADI Implementation

**BADI**: `USMD_RULE_SERVICE_BADI_MATL`  
**Method**: `CHECK_ENTITY`

**Purpose**: Custom validation before activation

```abap
*&---------------------------------------------------------------------*
*&  Implementation: Z_USMD_MATL_VALIDATION
*&  BADI: USMD_RULE_SERVICE_BADI_MATL
*&  Method: CHECK_ENTITY
*&---------------------------------------------------------------------*

METHOD if_usmd_rule_service_badi~check_entity.

  DATA: lv_matnr TYPE matnr,
        lv_maktx TYPE maktx,
        lv_count TYPE i.

  " Get material description
  READ TABLE it_entity INTO DATA(ls_entity)
    WITH KEY fieldname = 'MAKTX'.
  IF sy-subrc = 0.
    lv_maktx = ls_entity-value.
  ENDIF.

  " Duplicate description check
  SELECT COUNT(*)
    FROM makt
    INTO lv_count
    WHERE maktx = lv_maktx
      AND spras = sy-langu.

  IF lv_count > 0.
    " Add error message
    APPEND VALUE #(
      msgty = 'E'
      msgid = 'ZMDG_MESSAGES'
      msgno = '001'
      attr1 = lv_maktx
    ) TO et_message.
  ENDIF.

  " Mandatory field validation
  READ TABLE it_entity INTO ls_entity
    WITH KEY fieldname = 'MEINS'.
  IF sy-subrc <> 0 OR ls_entity-value IS INITIAL.
    APPEND VALUE #(
      msgty = 'E'
      msgid = 'ZMDG_MESSAGES'
      msgno = '002'
      attr1 = 'Base UOM'
    ) TO et_message.
  ENDIF.

ENDMETHOD.
```

### 2. IDOC Filter BADI

**BADI**: `USMD_IDOC_FILTER`  
**Method**: `FILTER_IDOC_DATA`

**Purpose**: Filter plant-specific data for each receiving system

```abap
*&---------------------------------------------------------------------*
*&  Implementation: Z_USMD_IDOC_FILTER
*&  BADI: USMD_IDOC_FILTER
*&  Method: FILTER_IDOC_DATA
*&---------------------------------------------------------------------*

METHOD if_usmd_idoc_filter~filter_idoc_data.

  DATA: lv_plant TYPE werks_d,
        lv_receiver TYPE edi_logsys.

  " Get receiver logical system
  lv_receiver = iv_receiver_ls.

  " Determine plant based on receiver
  CASE lv_receiver.
    WHEN 'PLANT1_100'.
      lv_plant = '1000'.
    WHEN 'PLANT2_100'.
      lv_plant = '2000'.
    WHEN 'PLANT3_100'.
      lv_plant = '3000'.
  ENDCASE.

  " Filter E1MARCM segments for specific plant only
  DELETE ct_idoc_data WHERE
    segnam = 'E1MARCM' AND
    sdata+3(4) <> lv_plant.  " WERKS field position

  " Set filter applied flag
  rv_filter_applied = abap_true.

ENDMETHOD.
```

### 3. Error Monitoring Report

**Program**: `Z_MDG_IDOC_ERROR_MONITOR`

**Purpose**: Monitor and reprocess failed IDOCs

```abap
*&---------------------------------------------------------------------*
*&  Report: Z_MDG_IDOC_ERROR_MONITOR
*&  Description: IDOC Error Monitoring and Reprocessing
*&---------------------------------------------------------------------*

REPORT z_mdg_idoc_error_monitor.

TABLES: edidc, edids.

PARAMETERS: p_date TYPE sydatum DEFAULT sy-datum,
            p_msgty TYPE edi_mestyp DEFAULT 'MATMAS',
            p_repro AS CHECKBOX.

DATA: it_errors TYPE TABLE OF edidc,
      lv_count TYPE i.

START-OF-SELECTION.

  " Select failed IDOCs
  SELECT *
    FROM edidc
    INTO TABLE it_errors
    WHERE mestyp = p_msgty
      AND credat = p_date
      AND status IN ('51', '64', '68').  " Error statuses

  lv_count = lines( it_errors ).

  WRITE: / 'Failed IDOCs found:', lv_count.
  SKIP 2.

  " Display errors
  LOOP AT it_errors INTO DATA(ls_error).
    WRITE: / 'IDOC Number:', ls_error-docnum,
           / 'Status:', ls_error-status,
           / 'Receiver:', ls_error-rcvprn.

    " Get error details
    SELECT SINGLE statxt
      FROM edids
      INTO @DATA(lv_statxt)
      WHERE docnum = @ls_error-docnum
      ORDER BY countr DESCENDING.

    WRITE: / 'Error:', lv_statxt.
    SKIP 1.

    " Reprocess if checkbox selected
    IF p_repro = abap_true.
      CALL FUNCTION 'EDI_DOCUMENT_REPROCESS_DIRECT'
        EXPORTING
          document_number = ls_error-docnum
        EXCEPTIONS
          OTHERS          = 1.

      IF sy-subrc = 0.
        WRITE: / '  >>> Reprocessed successfully', icon_led_green.
      ELSE.
        WRITE: / '  >>> Reprocessing failed', icon_led_red.
      ENDIF.
    ENDIF.

  ENDLOOP.

END-OF-SELECTION.
```

---

## Workflow Configuration

### Workflow Template

**Transaction**: PFTC  
**Task**: `WS99000076` (Standard MDG approval task)  
**Workflow Template**: `USMD_ATC_1ST`

### Configuration Steps

1. **Assign Workflow Template to CR Type**
   - Transaction: `USMD_RULE`
   - Rule: `USMD_RULE_WF_START`
   - Action: Map MAT01/MAT02/MAT03 → USMD_ATC_1ST

2. **Approver Determination**
   ```
   Material Type ROH → Material Manager (Plant)
   Material Type HALB → Production Manager
   Material Type FERT → Production Manager + Quality Manager
   ```

3. **Email Notification Template**
   ```
   Subject: Material &MATNR& - Approval Required
   
   Body:
   A new material change request requires your approval.
   
   Material Number: &MATNR&
   Description: &MAKTX&
   Change Request: &CR_NUMBER&
   Requester: &REQUESTER&
   
   Please review and approve/reject in SAP MDG.
   ```

---


### Monitoring & Alerting

**Daily Monitoring Report**:
- Transaction: `Z_MDG_IDOC_ERROR_MONITOR`
- Frequency: Hourly (scheduled job)
- Alerts: Email to MDG support team

**KPIs Tracked**:
- Total IDOCs sent (daily)
- Success rate percentage
- Average processing time
- Error trends by type

---

## Performance Considerations

### Optimization Techniques

1. **Batch Processing**: Group material activations for bulk IDOC generation
2. **Parallel Processing**: Enable parallel IDOC processing (RBDMOIND)
3. **Index Optimization**: Ensure EDIDC/EDID4 tables have proper indexes
4. **Archive Strategy**: Archive processed IDOCs after 90 days

### Expected Performance

| Metric | Target | Actual (Post-Implementation) |
|--------|--------|------------------------------|
| Activation Time | < 30 sec | 18-25 sec |
| IDOC Generation | < 1 min | 35-45 sec |
| IDOC Processing (Plant) | < 5 min | 2-3 min |
| End-to-End | < 10 min | 5-8 min |

---

## Security & Authorization

### MDG Authorizations

```
USMD_MODIFY: Material data maintenance
USMD_ACTIVATE: Activation authorization
USMD_APPROVE: Workflow approval
USMD_REJECT: Workflow rejection
```

### IDOC Authorizations

```
S_IDOCDEFT: IDOC definition authorization
S_IDOCMONI: IDOC monitoring authorization
S_ALE_INT: ALE integration authorization
```

**Document Prepared By**: Madhuri - SAP MDG Consultant  
**Technical Expertise**: MDG 8.0, IDOC Integration, BRF+, ABAP Development  
**Years of Experience**: 5+ years in SAP MDG
