# MDG Configuration Files

This folder contains MDG-specific configuration documentation and export files.

## Contents

### Data Model (`/data-model/`)

**Material Data Model Configuration**

Key configurations:
- Entity types: MATERIAL, MARA, MAKT, MARC, MBEW
- Relationships between entities
- Key attributes and field mappings

**Documentation**:
Detailed data model configuration is documented in `/docs/technical-design.md`

---

### Workflow (`/workflow/`)

**Workflow Templates and Configuration**

Implemented workflows:
- MAT01 - Create Material (Single-step approval)
- MAT02 - Change Material (Single-step approval)  
- MAT03 - Extend Material (Single-step approval)

**Workflow Template**: Z_WS_MDG_APPROVAL (Based on WS99000076)

---

### Validation Rules (`/validation-rules/`)

**BRF+ Rules Export**

Validation rules implemented:
1. **Duplicate Description Check**: Prevents duplicate material descriptions
2. **Mandatory Fields Check**: Validates required fields (MAKTX, MEINS, MTART, MATKL)
3. **Plant Existence Check**: Verifies plant code exists in T001W
4. **Material Type-Specific Rules**: Enforces material type business rules

**Implementation**: See `/src/abap/badi-implementations/zcl_usmd_matl_validation.abap`

---

## Configuration Export

To export your MDG configurations:

### Data Model Export
```
Transaction: USMD_MODEL
1. Select MATERIAL data model
2. Utilities → Export → Select export format
3. Save to file
```

### Workflow Export
```
Transaction: PFTC
1. Display workflow template Z_WS_MDG_APPROVAL
2. Workflow → Download
3. Save as .XML or .WF file
```

### BRF+ Rules Export
```
Transaction: BRF+
1. Navigate to application
2. Export → Select rules
3. Download as .XML
```

---

## Configuration Import (For New System)

When setting up in a new system:

1. **Import Data Model**
   - Transaction: USMD_MODEL
   - Import exported configuration
   - Activate data model

2. **Import Workflow**
   - Transaction: PFTC  
   - Upload workflow template
   - Configure agents/approvers

3. **Import BRF+ Rules**
   - Transaction: BRF+
   - Import application and rules
   - Assign to change request types

---

## Configuration Best Practices

### Data Model
- Always version control your data model changes
- Document custom attributes thoroughly
- Test in DEV before moving to QAS/PRD

### Workflow
- Keep workflows simple (avoid over-complication)
- Document approval paths clearly
- Set reasonable deadlines (2-3 days typical)
- Configure escalation for critical materials

### Validation Rules
- Balance between strict and flexible
- Provide clear error messages
- Consider warning vs error appropriately
- Test edge cases thoroughly

---

## Related Documentation

- **Setup Guide**: `/docs/setup-guide.md` - Step-by-step configuration
- **Technical Design**: `/docs/technical-design.md` - Architecture details
- **Testing Guide**: `/docs/testing-guide.md` - Validation test scenarios

---

**Maintained By**: Madhuri - SAP MDG Consultant  
**Last Updated**: May 2026
