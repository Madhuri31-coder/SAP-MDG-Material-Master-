*&---------------------------------------------------------------------*
*& Implementation: ZCL_USMD_MATL_VALIDATION
*& BADI: USMD_RULE_SERVICE_BADI_MATL
*& Purpose: Custom validations for Material Master MDG
*&---------------------------------------------------------------------*
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
