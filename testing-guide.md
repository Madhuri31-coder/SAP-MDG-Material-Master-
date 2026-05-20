# Testing Guide: SAP MDG Material Master with IDOC Distribution

## Table of Contents
1. [Test Strategy](#test-strategy)
2. [Test Scenarios](#test-scenarios)
3. [Test Data](#test-data)
4. [Test Execution](#test-execution)
5. [Test Results](#test-results)

---

## Test Strategy

### Testing Phases

```
Phase 1: Unit Testing (Week 5)
  ├─ Validation Rules Testing
  ├─ BADI Implementation Testing
  └─ Custom Program Testing

Phase 2: Integration Testing (Week 6-7)
  ├─ MDG-to-IDOC Flow Testing
  ├─ Multi-System Distribution Testing
  └─ Workflow Integration Testing

Phase 3: Performance Testing (Week 7)
  ├─ Load Testing (100+ materials)
  ├─ Concurrent User Testing
  └─ IDOC Volume Testing

Phase 4: User Acceptance Testing (Week 7)
  ├─ End-User Scenarios
  ├─ Process Validation
  └─ Training Validation
```

### Test Environment Setup

**Systems Required**:
```
DEV (Development)    - Initial development and unit testing
QAS (Quality)        - Integration testing
PRD (Production)     - Go-live and hypercare
```

**Test Data Requirements**:
- 50 test materials (various material types)
- 3 test plants configured
- 5 test users with different roles

---

## Test Scenarios

### Category 1: Happy Path Scenarios

#### TC-001: Create New Material with Single Plant

**Objective**: Verify material creation flows through MDG and distributes to one plant

**Preconditions**:
- User has USMD_MODIFY authorization
- Plant 1000 is configured

**Test Steps**:
```
1. Login to MDG with material creator role
2. Navigate to Create Material (CR Type: MAT01)
3. Enter material data:
   - Material Type: ROH (Raw Material)
   - Description: Steel Sheet Grade A2 - TEST
   - Base UOM: TON
   - Material Group: RM001
   - Plant: 1000
   - MRP Type: PD
   - MRP Controller: 001

4. Save as draft
5. Submit for approval
6. Login as approver
7. Approve the change request
8. Verify activation successful
```

**Expected Results**:
```
✓ Change request created successfully
✓ Workflow triggered - email sent to approver
✓ Activation completed without errors
✓ IDOC generated with MATMAS message type
✓ IDOC sent to PLANT1_100 (Status 03 - Passed to Port)
✓ IDOC processed in Plant 1 system (Status 53 - Posted)
✓ Material exists in Plant 1 MARA and MARC tables
```

**Verification Queries**:
```sql
-- Check material in MDG staging
SELECT * FROM usmd_mara WHERE matnr = '<TEST_MATNR>'

-- Check IDOC generation
SELECT * FROM edidc 
WHERE mestyp = 'MATMAS' 
  AND credat = sy-datum
ORDER BY cretim DESC

-- Check material in target system
SELECT * FROM mara WHERE matnr = '<TEST_MATNR>'
SELECT * FROM marc WHERE matnr = '<TEST_MATNR>' AND werks = '1000'
```

---

#### TC-002: Extend Existing Material to Multiple Plants

**Objective**: Verify material extension distributes to multiple plants

**Test Steps**:
```
1. Select existing material
2. Create change request (CR Type: MAT03)
3. Add plant data:
   - Plant 2000
   - Plant 3000
4. Submit and approve
5. Activate
```

**Expected Results**:
```
✓ 2 IDOCs generated (one per plant)
✓ IDOC 1 → PLANT2_100 (filtered for plant 2000)
✓ IDOC 2 → PLANT3_100 (filtered for plant 3000)
✓ Both IDOCs processed successfully
✓ Material exists in MARC for plants 2000 and 3000
```

---

#### TC-003: Change Material Description

**Objective**: Verify material changes trigger IDOC update

**Test Steps**:
```
1. Create change request (CR Type: MAT02)
2. Modify description: "Steel Sheet Grade A2 - Updated"
3. Submit, approve, activate
```

**Expected Results**:
```
✓ IDOC generated with update flag
✓ Description updated in all plant systems
✓ Audit log captures the change
```

---

### Category 2: Validation Testing

#### TC-004: Duplicate Material Description Check

**Objective**: Verify system prevents duplicate material descriptions

**Test Steps**:
```
1. Create material with description "Test Material ABC"
2. Activate successfully
3. Try to create another material with same description
```

**Expected Results**:
```
✓ Validation error message displayed
✓ Error: "Material description already exists"
✓ Change request cannot be activated
```

**Code Path**: BADI `ZCL_USMD_MATL_VALIDATION` → Method `CHECK_DUPLICATE_MATERIAL`

---

#### TC-005: Mandatory Field Validation

**Objective**: Verify mandatory fields are enforced

**Test Steps**:
```
1. Create material without description
2. Try to activate
```

**Expected Results**:
```
✓ Error: "Description is mandatory"
✓ Activation blocked
```

**Test Variations**:
- Missing Base UOM → Error
- Missing Material Type → Error
- Missing Material Group → Error

---

#### TC-006: Invalid Plant Code

**Objective**: Verify system validates plant existence

**Test Steps**:
```
1. Create material with plant code "9999" (non-existent)
2. Try to activate
```

**Expected Results**:
```
✓ Error: "Plant 9999 does not exist"
✓ Activation blocked
```

---

### Category 3: Workflow Testing

#### TC-007: Single-Step Approval Workflow

**Objective**: Verify workflow triggers and completes

**Test Steps**:
```
1. Create change request
2. Submit for approval
3. Check workflow work item created
4. Approve from SBWP
5. Verify activation
```

**Expected Results**:
```
✓ Work item created in SBWP
✓ Email sent to approver
✓ After approval, CR status = "Approved"
✓ Activation proceeds automatically
```

**Verification**:
- Transaction: `SBWP` → Check inbox
- Transaction: `SWI1` → Check workflow log

---

#### TC-008: Workflow Rejection

**Objective**: Verify rejection handling

**Test Steps**:
```
1. Create change request
2. Submit for approval
3. Reject with reason: "Incorrect material group"
4. Verify rejection
```

**Expected Results**:
```
✓ CR status = "Rejected"
✓ Rejection reason visible
✓ Requester notified via email
✓ CR can be edited and resubmitted
```

---

#### TC-009: Workflow Escalation (Deadline Exceeded)

**Objective**: Verify escalation after deadline

**Test Steps**:
```
1. Create change request
2. Wait for 2 days (deadline)
3. Check escalation
```

**Expected Results**:
```
✓ Escalation email sent to supervisor
✓ Work item still visible to original approver
✓ Reminder emails sent
```

---

### Category 4: IDOC Testing

#### TC-010: IDOC Generation for Create

**Objective**: Verify IDOC structure for new material

**Test Data**: Material M-TEST-001

**Expected IDOC Structure**:
```
E1MARAM (Header)
  MATNR = M-TEST-001
  MTART = ROH
  MEINS = TON

E1MAKTM (Description)
  MAKTX = Test Material 001
  SPRAS = EN

E1MARCM (Plant Data - Plant 1000)
  WERKS = 1000
  DISMM = PD
  DISPO = 001

E1MBEWM (Valuation - Plant 1000)
  BWKEY = 1000
  VPRSV = S
```

**Verification**:
- Transaction: `WE19` → Display IDOC
- Check all segments present
- Verify data accuracy

---

#### TC-011: IDOC Filtering by Plant

**Objective**: Verify plant-specific filtering works

**Test Steps**:
```
1. Create material with data for Plant 1000 and 2000
2. Activate
3. Check IDOC sent to PLANT1_100
4. Verify it contains only Plant 1000 data
```

**Expected Results**:
```
✓ IDOC to PLANT1_100 has E1MARCM only for WERKS = 1000
✓ IDOC to PLANT2_100 has E1MARCM only for WERKS = 2000
✓ No cross-plant data leakage
```

**Code Path**: BADI `ZCL_USMD_IDOC_FILTER` → Method `FILTER_PLANT_DATA`

---

#### TC-012: IDOC Error Handling - Status 51

**Objective**: Verify handling of application errors

**Test Steps**:
```
1. Create material with invalid data (e.g., invalid UOM)
2. Activate and send IDOC
3. Check IDOC status in target system
```

**Expected Results**:
```
✓ IDOC status = 51 (Application Error)
✓ Error message visible in WE02
✓ Error logged in monitoring report
✓ Email alert sent
```

---

#### TC-013: IDOC Error Handling - Status 68

**Objective**: Verify handling of communication errors

**Test Steps**:
```
1. Disable RFC destination to Plant 1
2. Create and activate material
3. Check IDOC status
```

**Expected Results**:
```
✓ IDOC status = 68 (Error in ALE Service)
✓ Auto-retry triggered after 5 minutes
✓ Error visible in monitoring report
```

---

### Category 5: Error Monitoring

#### TC-014: Error Monitoring Report

**Objective**: Verify error monitoring program works

**Test Steps**:
```
1. Create 5 materials with errors (intentional)
2. Run program Z_MDG_IDOC_ERROR_MONITOR
3. Check report output
```

**Expected Results**:
```
✓ Report displays all 5 error IDOCs
✓ Shows IDOC number, status, error text
✓ Material numbers displayed correctly
```

---

#### TC-015: Automatic IDOC Reprocessing

**Objective**: Verify reprocessing works

**Test Steps**:
```
1. Create IDOC with status 68
2. Run monitoring report with reprocess flag
3. Check IDOC status after reprocessing
```

**Expected Results**:
```
✓ IDOC status changes from 68 → 03 → 53
✓ Material successfully created in target
✓ Success message in report
```

---

### Category 6: Performance Testing

#### TC-016: Bulk Material Creation

**Objective**: Test system performance with high volume

**Test Data**: 100 materials

**Test Steps**:
```
1. Upload 100 materials via LSMW
2. Create change requests (batch)
3. Approve all
4. Measure activation time
```

**Expected Results**:
```
✓ All 100 materials activated within 30 minutes
✓ 100 IDOCs generated
✓ No system performance degradation
✓ All IDOCs processed successfully
```

**Performance Metrics**:
```
Average activation time per material: < 30 seconds
IDOC generation time: < 1 minute
End-to-end processing: < 10 minutes per material
```

---

#### TC-017: Concurrent User Testing

**Objective**: Test with multiple users creating materials simultaneously

**Test Steps**:
```
1. 5 users create materials simultaneously
2. Each creates 10 materials
3. Monitor system performance
```

**Expected Results**:
```
✓ No locking issues
✓ No performance degradation
✓ All materials processed successfully
```

---

## Test Data

### Material Type Distribution

| Material Type | Description | Quantity | Plant Data |
|--------------|-------------|----------|------------|
| ROH | Raw Materials | 20 | 1000, 2000 |
| HALB | Semi-Finished | 15 | 1000, 2000, 3000 |
| FERT | Finished Products | 10 | All plants |
| HAWA | Trading Goods | 5 | 1000 |

### Test Users

| User ID | Role | Authorization | Email |
|---------|------|---------------|-------|
| MDGUSER01 | Material Creator | USMD_MODIFY | user01@test.com |
| MDGUSER02 | Material Creator | USMD_MODIFY | user02@test.com |
| MDGAPPR01 | Approver | USMD_APPROVE | approver01@test.com |
| MDGAPPR02 | Approver | USMD_APPROVE | approver02@test.com |
| MDGADM01 | Administrator | USMD_ALL | admin01@test.com |

---

## Test Execution

### Test Execution Schedule

**Week 5: Unit Testing**
- Days 1-2: Validation testing (TC-004 to TC-006)
- Days 3-4: Workflow testing (TC-007 to TC-009)
- Day 5: Error handling (TC-014, TC-015)

**Week 6: Integration Testing**
- Days 1-2: Happy path scenarios (TC-001 to TC-003)
- Days 3-4: IDOC testing (TC-010 to TC-013)
- Day 5: Defect fixing

**Week 7: Performance & UAT**
- Days 1-2: Performance testing (TC-016, TC-017)
- Days 3-5: User acceptance testing

---

## Test Results Summary

### Test Execution Status

| Category | Total Tests | Passed | Failed | Blocked | Pass Rate |
|----------|-------------|--------|--------|---------|-----------|
| Happy Path | 3 | 3 | 0 | 0 | 100% |
| Validation | 3 | 3 | 0 | 0 | 100% |
| Workflow | 3 | 3 | 0 | 0 | 100% |
| IDOC | 4 | 4 | 0 | 0 | 100% |
| Error Handling | 2 | 2 | 0 | 0 | 100% |
| Performance | 2 | 2 | 0 | 0 | 100% |
| **TOTAL** | **17** | **17** | **0** | **0** | **100%** |

---

### Defects Log

| Defect ID | Description | Severity | Status | Resolution |
|-----------|-------------|----------|--------|------------|
| DEF-001 | Workflow email not sent | Medium | Closed | Fixed SMTP configuration |
| DEF-002 | IDOC status 51 for UOM | Low | Closed | Added UOM validation |
| DEF-003 | Performance issue with 100+ materials | High | Closed | Enabled parallel processing |

---

### Performance Test Results

#### Bulk Processing Results

```
Test Date: Nov 10, 2023
Materials Processed: 100
Total Time: 22 minutes
Average Time per Material: 13.2 seconds

Breakdown:
- Change Request Creation: 2 minutes
- Validation: 3 minutes
- Workflow Approval: 5 minutes
- Activation: 8 minutes
- IDOC Generation & Distribution: 4 minutes
```

**Conclusion**: ✅ Meets performance target (< 30 minutes for 100 materials)

---

## Go-Live Readiness Checklist

### Technical Readiness
- [x] All test scenarios passed
- [x] No critical defects open
- [x] Performance targets met
- [x] Error monitoring configured
- [x] Backup & rollback plan ready

### Business Readiness
- [x] User training completed
- [x] Process documentation finalized
- [x] Support team trained
- [x] Business sign-off obtained

### Operational Readiness
- [x] Production data migrated
- [x] Monitoring dashboards configured
- [x] Support processes defined
- [x] Hypercare schedule planned

---

## Appendix: Test Scripts

### Script: Check IDOC Status

```abap
* Quick check for IDOC processing status
SELECT docnum, status, credat, cretim
  FROM edidc
  WHERE mestyp = 'MATMAS'
    AND credat = sy-datum
  ORDER BY cretim DESCENDING.
```

### Script: Material Existence Check

```abap
* Check if material exists in all systems
SELECT matnr, ersda, ernam
  FROM mara
  WHERE matnr = 'M-TEST-001'.

SELECT matnr, werks, ersda
  FROM marc
  WHERE matnr = 'M-TEST-001'.
```

---

**Document Version**: 1.0  
**Test Lead**: Madhuri - SAP MDG Consultant  
**Testing Period**: Weeks 5-7 of Implementation  
**Sign-off Date**: Nov 15, 2023
