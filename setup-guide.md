# Setup Guide: SAP MDG Material Master with IDOC Distribution

## Prerequisites

### System Requirements
- SAP ECC 6.0 or S/4HANA with MDG component installed
- Minimum MDG version: 8.0
- ALE/IDOC configuration authorization
- Workflow configuration access
- ABAP development authorization

### Access Requirements
- Transaction codes: USMD_MODEL, USMD_RULE, USMD_UI_CONF, WE20, BD64, PFTC
- Authorization objects: USMD_MODIFY, S_IDOCDEFT, PFAC
- Development key for custom development

---

## Implementation Roadmap

```
Week 1-2: MDG Configuration
  ├─ Data Model Setup
  ├─ UI Configuration
  └─ Validation Rules

Week 3-4: IDOC Integration
  ├─ Partner Profiles
  ├─ Distribution Model
  └─ Testing

Week 5-6: Custom Development
  ├─ BADI Implementation
  ├─ Error Monitoring
  └─ Unit Testing

Week 7: Integration Testing
Week 8: Go-Live & Support
```

---

## Step-by-Step Configuration

### Phase 1: MDG Data Model Configuration

#### Step 1.1: Activate Material Data Model

**Transaction**: `USMD_MODEL`

1. Navigate to USMD_MODEL
2. Select data model: **MATERIAL**
3. Click "Edit" button
4. Go to **Entity Types** tab
5. Ensure following entities are active:
   - MATERIAL (Main)
   - MARA (General Data)
   - MAKT (Descriptions)
   - MARC (Plant Data)
   - MBEW (Valuation)
   - MEAN (EAN/UPC)

6. Click "Check" → "Activate"

**Verification**:
```
✓ Data model status = Active
✓ All required entities visible in dropdown
```

---

#### Step 1.2: Configure Change Request Types

**Transaction**: `USMD_CREQUEST_TYPE` or `USMDCRTP`

**Create CR Type: MAT01 (Create Material)**
```
CR Type:        MAT01
Description:    Create Material
Data Model:     MATERIAL
Step Type:      Single-Step
Activation:     With Workflow
Allow Draft:    Yes
```

**Create CR Type: MAT02 (Change Material)**
```
CR Type:        MAT02
Description:    Change Material
Data Model:     MATERIAL
Step Type:      Single-Step
Activation:     With Workflow
Allow Draft:    Yes
```

**Create CR Type: MAT03 (Extend Material)**
```
CR Type:        MAT03
Description:    Extend Material to Plant
Data Model:     MATERIAL
Step Type:      Single-Step
Activation:     With Workflow
Allow Draft:    Yes
```

---

#### Step 1.3: Configure UI

**Transaction**: `USMD_UI_CONF`

1. Select Data Model: **MATERIAL**
2. Create UI Configuration

**General Data Tab Configuration**:
```
Field Name        Display   Mandatory   Read-Only
──────────────────────────────────────────────────
MATNR             Yes       Yes         No
MAKTX             Yes       Yes         No
MTART             Yes       Yes         No
MEINS             Yes       Yes         No
MATKL             Yes       Yes         No
BISMT             Yes       No          No
```

**Plant Data Tab Configuration**:
```
Field Name        Display   Mandatory   Read-Only
──────────────────────────────────────────────────
WERKS             Yes       Yes         No
DISMM             Yes       Yes         No
DISPO             Yes       No          No
DISLS             Yes       No          No
EISBE             Yes       No          No
```

**Field Groups**:
- Create field group "Basic Data" with MATNR, MAKTX, MTART, MEINS
- Create field group "Classification" with MATKL, BISMT
- Create field group "Plant MRP" with DISMM, DISPO, DISLS, EISBE

---

### Phase 2: Validation Rules (BRF+)

#### Step 2.1: Create Duplicate Check Rule

**Transaction**: `BRF+` or `USMD_RULE`

**Rule: Duplicate Material Description Check**

1. Go to USMD_RULE
2. Create new rule:
   ```
   Rule Name:    DUPLICATE_MAKTX_CHECK
   Description:  Check for duplicate material description
   Rule Type:    Validation Rule
   ```

3. Define Rule Logic:
   ```
   IF COUNT(MAKT-MAKTX) WHERE MAKTX = CURRENT_MAKTX > 0
   THEN
     MESSAGE-TYPE = 'E'
     MESSAGE-TEXT = 'Material description already exists'
   ENDIF
   ```

4. Assign to CR Types: MAT01, MAT02, MAT03

---

#### Step 2.2: Create Mandatory Field Rule

**Rule: Mandatory Fields Validation**

```
Rule Name:    MANDATORY_FIELDS_CHECK
Description:  Check mandatory fields before activation

Logic:
  IF MAKTX IS INITIAL
    THEN ERROR 'Description is mandatory'
  
  IF MEINS IS INITIAL
    THEN ERROR 'Base UOM is mandatory'
  
  IF MTART IS INITIAL
    THEN ERROR 'Material Type is mandatory'
```

---

### Phase 3: Workflow Configuration

#### Step 3.1: Configure Workflow Template

**Transaction**: `PFTC`

1. Copy standard workflow: **WS99000076**
2. Create custom workflow: **Z_WS_MDG_APPROVAL**

**Configuration**:
```
Task:              Z_APPROVE_MATERIAL
Agent:             Position → Material Manager
Deadline:          2 days
Escalation:        Send to supervisor after deadline
Email Template:    Enable email notifications
```

---

#### Step 3.2: Link Workflow to CR Types

**Transaction**: `USMD_RULE`

1. Navigate to Process Modeling
2. For each CR Type (MAT01, MAT02, MAT03):
   ```
   Event:     Start of Change Request
   Action:    Start Workflow
   Workflow:  Z_WS_MDG_APPROVAL
   ```

---

### Phase 4: IDOC Configuration

#### Step 4.1: Define Logical Systems

**Transaction**: `SALE` → **Basic Settings** → **Logical Systems**

Create logical systems:
```
Logical System     Description
────────────────────────────────────────
MDGHUB_100         MDG Central Hub
PLANT1_100         Plant 1 System
PLANT2_100         Plant 2 System
PLANT3_100         Plant 3 System
```

Assign to clients via `SCC4`.

---

#### Step 4.2: Create RFC Destinations

**Transaction**: `SM59`

**For Plant 1**:
```
RFC Destination:  SAPPLANT1
Connection Type:  3 (ABAP)
Target Host:      plant1.company.com
System Number:    00
Client:           100
```

Repeat for Plant 2 and Plant 3.

**Test Connection**: Click "Connection Test" and "Remote Logon"

---

#### Step 4.3: Configure Ports

**Transaction**: `WE21`

**Create tRFC Port for Plant 1**:
```
Port:             SAPPLANT1
Description:      tRFC Port to Plant 1
RFC Destination:  SAPPLANT1
```

Repeat for Plant 2 and Plant 3.

---

#### Step 4.4: Configure Partner Profiles

**Transaction**: `WE20`

**Outbound Parameters (MDG Hub)**:

For Partner: **PLANT1_100** (LS Type)
```
Outbound Parameters:
  Message Type:      MATMAS
  Receiver Port:     SAPPLANT1
  Pack Size:         1
  Output Mode:       Transfer IDocs Immediately
  Basic Type:        MATMAS05
  Segment Release:   (Leave blank)
```

Repeat for PLANT2_100 and PLANT3_100.

---

**Inbound Parameters (Plant Systems)**:

On each plant system, configure:

For Partner: **MDGHUB_100** (LS Type)
```
Inbound Parameters:
  Message Type:       MATMAS
  Process Code:       MATM
  Processing Type:    Trigger Immediately
  Process by Function: (Standard)
```

---

#### Step 4.5: Create Distribution Model

**Transaction**: `BD64`

1. Create new model: **Z_MDG_MATMAS_DIST**
2. Add model view:
   ```
   View Name:        Material Master Distribution
   Sender:           MDGHUB_100
   ```

3. Add receivers with filters:

**For PLANT1_100**:
```
Message Type:     MATMAS
Filter Object:    MARC
Filter:           WERKS = 1000
```

**For PLANT2_100**:
```
Message Type:     MATMAS
Filter Object:    MARC
Filter:           WERKS = 2000
```

**For PLANT3_100**:
```
Message Type:     MATMAS
Filter Object:    MARC
Filter:           WERKS = 3000
```

4. Generate partner profiles: **Environment** → **Generate Partner Profiles**

---

#### Step 4.6: Configure IDOC Output

**Transaction**: `NACE`

1. Application: **MD** (Material Master)
2. Output Type: **MAT** or create custom: **ZMAT**
3. Processing Routines:
   ```
   Program:          RMATMA01
   Form Routine:     ENTRY_MAT
   ```

4. Partner Functions: Configure as needed

---

### Phase 5: Custom Development

#### Step 5.1: Create BADI Implementation

**Transaction**: `SE19`

**Enhancement Spot**: `USMD_CUSTOMER`

1. Create implementation: **Z_USMD_MATL_IMPL**
2. Add BADI: **USMD_RULE_SERVICE_BADI_MATL**
3. Implementing Class: **ZCL_USMD_MATL_VALIDATION**
4. Copy code from: `/src/abap/badi-implementations/zcl_usmd_matl_validation.abap`
5. Activate

**Verification**:
- Go to SE18 → Check BADI implementation is active
- Test with dummy change request

---

#### Step 5.2: Create IDOC Filter BADI

**BADI**: `USMD_IDOC_FILTER`

1. Create implementation: **Z_USMD_IDOC_FILTER_IMPL**
2. Implementing Class: **ZCL_USMD_IDOC_FILTER**
3. Copy code from: `/src/abap/idoc-enhancements/zcl_usmd_idoc_filter.abap`
4. Activate

---

#### Step 5.3: Create Error Monitoring Program

**Transaction**: `SE38`

1. Create program: **Z_MDG_IDOC_ERROR_MONITOR**
2. Copy code from: `/src/abap/error-handling/z_mdg_idoc_error_monitor.abap`
3. Activate
4. Create transaction code: **ZIDOCMON**

**Schedule as Background Job**:
- Transaction: `SM36`
- Job Name: **Z_MDG_IDOC_MONITOR_HOURLY**
- Frequency: Hourly
- Variant: Create with default parameters

---

### Phase 6: Testing

#### Step 6.1: Unit Testing

**Test Validation Rules**:
1. Create material with duplicate description → Should show error
2. Create material without mandatory fields → Should show error
3. Enter invalid plant code → Should show error

**Test Workflow**:
1. Create change request → Check workflow triggered
2. Verify email notification sent
3. Approve/reject → Check status change

---

#### Step 6.2: Integration Testing

**Test IDOC Generation**:
1. Create material with plant data
2. Activate change request
3. Check IDOC generated: `WE02`
4. Verify IDOC sent to correct plant: `WE05`

**Test IDOC Processing (Plant System)**:
1. Check IDOC received: `WE02`
2. Verify material created in MARA/MARC
3. Check data accuracy

---

#### Step 6.3: Error Scenario Testing

**Test Error Handling**:
1. Simulate communication error → Check auto-retry
2. Create invalid material data → Check error logged
3. Run error monitor → Verify reprocessing works

---

## Post-Implementation Tasks

### 1. User Training
- Train material master data stewards
- Train approvers on workflow
- Document process for end users

### 2. Monitoring Setup
- Schedule error monitoring job
- Set up email alerts
- Create dashboard for KPIs

### 3. Documentation
- Update process documentation
- Create user guides
- Document troubleshooting steps

---

## Troubleshooting Guide

### Issue: IDOC Not Generated

**Symptoms**: Activation successful but no IDOC created

**Checks**:
1. Check NACE configuration for output type
2. Verify distribution model (BD64)
3. Check partner profile (WE20)
4. Review application log: Transaction `SLG1`

**Solution**:
```
Transaction: WE19 (IDOC Test Tool)
- Create test IDOC manually
- Process to identify exact error
```

---

### Issue: IDOC Failed with Status 51

**Symptoms**: IDOC shows status 51 in WE02

**Meaning**: Application error in receiving system

**Resolution**:
1. Check error details in WE02
2. Review data issues (missing mandatory fields, invalid values)
3. Correct data in MDG
4. Reactivate change request
5. Or manually reprocess IDOC after correction

---

### Issue: Validation Not Triggering

**Symptoms**: Duplicate materials being created despite validation

**Checks**:
1. Check BADI is active: `SE19`
2. Verify rule assignment: `USMD_RULE`
3. Check CR type configuration

**Debug**:
```
1. Set breakpoint in BADI class
2. Create test change request
3. Check if BADI method is called
```

---

## Performance Optimization

### Bulk Material Upload
For mass material creation:
```
1. Use LSMW or eCATT for bulk upload
2. Group materials by plant for efficient IDOC generation
3. Schedule activation during off-peak hours
```

### IDOC Processing
```
1. Enable parallel processing: RBDMOIND
2. Increase work process count
3. Archive old IDOCs regularly
```

---

## Contact & Support

**For IDOC Issues**:
- IDOC Monitor: Run Z_MDG_IDOC_ERROR_MONITOR daily

---

**Document Version**: 1.0  
**Prepared By**: Madhuri - SAP MDG Consultant  

