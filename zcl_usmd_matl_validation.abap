*&---------------------------------------------------------------------*
*& Implementation: ZCL_USMD_MATL_VALIDATION
*& BADI: USMD_RULE_SERVICE_BADI_MATL
*& Purpose: Custom validations for Material Master MDG
*&---------------------------------------------------------------------*
*&
*& DESIGN WALKTHROUGH
*& ==================
*& WHY THIS BADI?
*&   SAP MDG triggers USMD_RULE_SERVICE_BADI_MATL at the validation
*&   step of every change request lifecycle — before activation.
*&   This is the correct interception point because:
*&     (a) It runs AFTER the user submits data but BEFORE it gets
*&         written to the active area, so we can block bad data early.
*&     (b) It integrates with the MDG message framework, so errors
*&         appear inline on the MDG UI rather than as a dump.
*&
*& WHY FOUR SEPARATE METHODS?
*&   Each validation concern is isolated in its own private method.
*&   This means:
*&     - Individual validations can be unit-tested independently
*&     - A failure in one check does NOT abort the others — the user
*&       sees ALL errors at once instead of one at a time
*&     - New validations can be added without touching existing logic
*&
*& WHY CHECK MAKT FOR DUPLICATES?
*&   Material descriptions are stored per language in MAKT. We check
*&   the active (production) table rather than the MDG staging area
*&   to catch conflicts with already-activated materials. The current
*&   material is excluded from the check using <> iv_matnr.
*&
*& WHY MATERIAL-TYPE SPECIFIC RULES?
*&   Business rules differ by material type (ROH=Raw, FERT=Finished,
*&   HALB=Semi-finished). Applying uniform rules across all types
*&   would either block valid data or miss real errors. The CASE
*&   structure makes it easy to extend for additional types (HAWA,
*&   DIEN, etc.) without restructuring the class.
*&
*& NOTE ON MESSAGE CLASS ZMDG_MSG:
*&   Message numbers are structured as:
*&     001 = Duplicate description
*&     002 = Mandatory field missing
*&     003 = Plant does not exist
*&     004-006 = Material type specific warnings/errors
*&
*&---------------------------------------------------------------------*
CLASS zcl_usmd_matl_validation DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_usmd_rule_service_badi.

  PRIVATE SECTION.
    METHODS:
      check_duplicate_material
        IMPORTING
          iv_matnr TYPE matnr
          iv_maktx TYPE maktx
        EXPORTING
          et_message TYPE usmd_t_message,

      check_mandatory_fields
        IMPORTING
          it_entity TYPE usmd_t_entity
        EXPORTING
          et_message TYPE usmd_t_message,

      check_plant_existence
        IMPORTING
          iv_werks TYPE werks_d
        EXPORTING
          et_message TYPE usmd_t_message,

      check_material_type_specific
        IMPORTING
          iv_mtart TYPE mtart
          it_entity TYPE usmd_t_entity
        EXPORTING
          et_message TYPE usmd_t_message.
ENDCLASS.

CLASS zcl_usmd_matl_validation IMPLEMENTATION.

*&---------------------------------------------------------------------*
*& Main CHECK_ENTITY Method (Called by MDG Framework)
*&
*& DESIGN NOTE: We deliberately do NOT exit early on first error.
*& All four checks run regardless of prior failures, so the user
*& sees the complete list of issues in a single submit cycle.
*& Each check writes to a local lt_messages buffer which is then
*& appended to et_message — this avoids accidental overwrites.
*&---------------------------------------------------------------------*
  METHOD if_usmd_rule_service_badi~check_entity.

    DATA: lt_messages TYPE usmd_t_message,
          lv_matnr    TYPE matnr,
          lv_maktx    TYPE maktx,
          lv_mtart    TYPE mtart,
          lv_meins    TYPE meins,
          lv_werks    TYPE werks_d.

    " Extract key field values from entity data
    READ TABLE it_entity INTO DATA(ls_entity)
      WITH KEY fieldname = 'MATNR'.
    IF sy-subrc = 0.
      lv_matnr = ls_entity-value.
    ENDIF.

    READ TABLE it_entity INTO ls_entity
      WITH KEY fieldname = 'MAKTX'.
    IF sy-subrc = 0.
      lv_maktx = ls_entity-value.
    ENDIF.

    READ TABLE it_entity INTO ls_entity
      WITH KEY fieldname = 'MTART'.
    IF sy-subrc = 0.
      lv_mtart = ls_entity-value.
    ENDIF.

    READ TABLE it_entity INTO ls_entity
      WITH KEY fieldname = 'WERKS'.
    IF sy-subrc = 0.
      lv_werks = ls_entity-value.
    ENDIF.

    " Validation 1: Check duplicate material description
    check_duplicate_material(
      EXPORTING
        iv_matnr   = lv_matnr
        iv_maktx   = lv_maktx
      IMPORTING
        et_message = lt_messages
    ).
    APPEND LINES OF lt_messages TO et_message.
    CLEAR lt_messages.

    " Validation 2: Check mandatory fields
    check_mandatory_fields(
      EXPORTING
        it_entity  = it_entity
      IMPORTING
        et_message = lt_messages
    ).
    APPEND LINES OF lt_messages TO et_message.
    CLEAR lt_messages.

    " Validation 3: Check plant existence (if plant data present)
    IF lv_werks IS NOT INITIAL.
      check_plant_existence(
        EXPORTING
          iv_werks   = lv_werks
        IMPORTING
          et_message = lt_messages
      ).
      APPEND LINES OF lt_messages TO et_message.
      CLEAR lt_messages.
    ENDIF.

    " Validation 4: Material type-specific validations
    IF lv_mtart IS NOT INITIAL.
      check_material_type_specific(
        EXPORTING
          iv_mtart   = lv_mtart
          it_entity  = it_entity
        IMPORTING
          et_message = lt_messages
      ).
      APPEND LINES OF lt_messages TO et_message.
    ENDIF.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Check for duplicate material description
*&
*& DESIGN NOTE: We query MAKT (active area) filtered by current
*& logon language (sy-langu). Cross-language duplicates are out of
*& scope — different language teams manage their own descriptions.
*& The <> iv_matnr exclusion is critical: without it, editing an
*& existing material would always trigger a false duplicate error
*& against itself.
*&---------------------------------------------------------------------*
  METHOD check_duplicate_material.

    DATA: lv_count TYPE i.

    IF iv_maktx IS INITIAL.
      RETURN.
    ENDIF.

    " Check if description already exists (excluding current material)
    SELECT COUNT(*)
      FROM makt
      INTO lv_count
      WHERE maktx = iv_maktx
        AND spras = sy-langu
        AND matnr <> iv_matnr.

    IF lv_count > 0.
      APPEND VALUE #(
        msgty = 'E'
        msgid = 'ZMDG_MSG'
        msgno = '001'
        attr1 = 'Material description'
        attr2 = iv_maktx
        attr3 = 'already exists'
      ) TO et_message.
    ENDIF.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Check mandatory fields
*&
*& DESIGN NOTE: The mandatory field list is defined inline here for
*& simplicity in this portfolio implementation. In a production
*& system, this list would be maintained in a custom configuration
*& table (e.g. ZMDG_MAND_FIELDS) so business users can adjust
*& requirements without a transport request.
*&
*& Fields checked: MAKTX (Description), MEINS (Base UOM),
*&                 MTART (Material Type), MATKL (Material Group)
*&---------------------------------------------------------------------*
  METHOD check_mandatory_fields.

    DATA: lt_mandatory_fields TYPE TABLE OF fieldname,
          lv_field_value      TYPE string.

    " Define mandatory fields
    APPEND: 'MAKTX' TO lt_mandatory_fields,   " Description
            'MEINS' TO lt_mandatory_fields,   " Base UOM
            'MTART' TO lt_mandatory_fields,   " Material Type
            'MATKL' TO lt_mandatory_fields.   " Material Group

    " Check each mandatory field
    LOOP AT lt_mandatory_fields INTO DATA(lv_fieldname).
      READ TABLE it_entity INTO DATA(ls_entity)
        WITH KEY fieldname = lv_fieldname.

      IF sy-subrc <> 0 OR ls_entity-value IS INITIAL.
        APPEND VALUE #(
          msgty = 'E'
          msgid = 'ZMDG_MSG'
          msgno = '002'
          attr1 = lv_fieldname
          attr2 = 'is mandatory'
        ) TO et_message.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Check if plant exists in T001W
*&
*& DESIGN NOTE: T001W is the standard SAP plant master table.
*& We validate against it rather than a custom table to ensure
*& the plant is genuinely active in the system landscape.
*& This prevents IDOC distribution failures downstream — if the
*& plant doesn't exist here, the MATMAS IDOC will fail at the
*& receiving system too.
*&---------------------------------------------------------------------*
  METHOD check_plant_existence.

    DATA: lv_exists TYPE abap_bool.

    IF iv_werks IS INITIAL.
      RETURN.
    ENDIF.

    SELECT SINGLE @abap_true
      FROM t001w
      INTO lv_exists
      WHERE werks = iv_werks.

    IF sy-subrc <> 0.
      APPEND VALUE #(
        msgty = 'E'
        msgid = 'ZMDG_MSG'
        msgno = '003'
        attr1 = 'Plant'
        attr2 = iv_werks
        attr3 = 'does not exist'
      ) TO et_message.
    ENDIF.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Material type-specific validations
*&
*& DESIGN NOTE: Each WHEN block represents a different governance
*& policy agreed with the business:
*&
*&   ROH (Raw Materials): Material group must start with 'RM' prefix
*&     — enforces the company's material group naming convention for
*&     procurement categorization and spend analytics.
*&
*&   FERT (Finished Products): Base UOM should be 'PC' (Pieces)
*&     — issued as a Warning (W) not Error (E) because edge cases
*&     exist (e.g. bulk liquids measured in LT). Business wanted
*&     visibility without hard blocking.
*&
*&   HALB (Semi-Finished): Material group is mandatory
*&     — stricter than the general mandatory check because HALB
*&     materials feed production BOMs and incorrect grouping causes
*&     costing errors.
*&---------------------------------------------------------------------*
  METHOD check_material_type_specific.

    DATA: lv_matkl TYPE matkl,
          lv_meins TYPE meins.

    " Get material group
    READ TABLE it_entity INTO DATA(ls_entity)
      WITH KEY fieldname = 'MATKL'.
    IF sy-subrc = 0.
      lv_matkl = ls_entity-value.
    ENDIF.

    " Get base UOM
    READ TABLE it_entity INTO ls_entity
      WITH KEY fieldname = 'MEINS'.
    IF sy-subrc = 0.
      lv_meins = ls_entity-value.
    ENDIF.

    CASE iv_mtart.

      WHEN 'ROH'.   " Raw Materials
        " Must have material group starting with 'RM'
        IF lv_matkl IS NOT INITIAL AND lv_matkl(2) <> 'RM'.
          APPEND VALUE #(
            msgty = 'W'
            msgid = 'ZMDG_MSG'
            msgno = '004'
            attr1 = 'Raw materials should have material group starting with RM'
          ) TO et_message.
        ENDIF.

      WHEN 'FERT'.  " Finished Products
        " Must have base UOM as PC (Pieces)
        IF lv_meins IS NOT INITIAL AND lv_meins <> 'PC'.
          APPEND VALUE #(
            msgty = 'W'
            msgid = 'ZMDG_MSG'
            msgno = '005'
            attr1 = 'Finished products typically use PC as base UOM'
          ) TO et_message.
        ENDIF.

      WHEN 'HALB'.  " Semi-Finished
        " Check if material group is defined
        IF lv_matkl IS INITIAL.
          APPEND VALUE #(
            msgty = 'E'
            msgid = 'ZMDG_MSG'
            msgno = '006'
            attr1 = 'Material group is mandatory for semi-finished products'
          ) TO et_message.
        ENDIF.

    ENDCASE.

  ENDMETHOD.

ENDCLASS.
