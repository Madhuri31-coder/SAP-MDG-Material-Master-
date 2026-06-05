*&---------------------------------------------------------------------*
*& Implementation: ZCL_USMD_IDOC_FILTER
*& BADI: USMD_IDOC_FILTER
*& Purpose: Filter plant-specific data for IDOC distribution
*&---------------------------------------------------------------------*
*&
*& DESIGN WALKTHROUGH
*& ==================
*& WHY THIS BADI?
*&   When MDG activates a material change request, SAP triggers DRF
*&   (Data Replication Framework) to distribute the change to all
*&   configured receivers via MATMAS05 IDOCs. Without filtering, every
*&   receiver gets the COMPLETE material — including plant data for
*&   plants that don't belong to that receiver's system.
*&

*&---------------------------------------------------------------------*
CLASS zcl_usmd_idoc_filter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_usmd_idoc_filter.

  PRIVATE SECTION.
    METHODS:
      get_plant_for_receiver
        IMPORTING
          iv_receiver_ls        TYPE edi_logsys
        RETURNING
          VALUE(rv_plant)       TYPE werks_d,

      filter_plant_data
        IMPORTING
          iv_plant              TYPE werks_d
        CHANGING
          ct_idoc_data          TYPE edidd_tt,

      filter_accounting_data
        IMPORTING
          iv_plant              TYPE werks_d
        CHANGING
          ct_idoc_data          TYPE edidd_tt,

      add_custom_segments
        IMPORTING
          iv_receiver_ls        TYPE edi_logsys
        CHANGING
          ct_idoc_data          TYPE edidd_tt.
ENDCLASS.

CLASS zcl_usmd_idoc_filter IMPLEMENTATION.

*&---------------------------------------------------------------------*
*& Main FILTER_IDOC_DATA Method
*&---------------------------------------------------------------------*
  METHOD if_usmd_idoc_filter~filter_idoc_data.

    DATA: lv_plant TYPE werks_d.

    " Determine target plant based on receiver logical system
    lv_plant = get_plant_for_receiver( iv_receiver_ls ).

    IF lv_plant IS INITIAL.
      " No filtering needed if plant cannot be determined
      rv_filter_applied = abap_false.
      RETURN.
    ENDIF.

    " Filter plant-specific data (E1MARCM segments)
    filter_plant_data(
      EXPORTING
        iv_plant     = lv_plant
      CHANGING
        ct_idoc_data = ct_idoc_data
    ).

    " Filter accounting data (E1MBEWM segments)
    filter_accounting_data(
      EXPORTING
        iv_plant     = lv_plant
      CHANGING
        ct_idoc_data = ct_idoc_data
    ).

    " Add custom segments if needed
    add_custom_segments(
      EXPORTING
        iv_receiver_ls = iv_receiver_ls
      CHANGING
        ct_idoc_data   = ct_idoc_data
    ).

    rv_filter_applied = abap_true.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Determine plant code from receiver logical system
*&---------------------------------------------------------------------*
  METHOD get_plant_for_receiver.

    " Mapping between logical systems and plants
    " In real implementation, this would be maintained in a custom table
    CASE iv_receiver_ls.
      WHEN 'PLANT1_100'.
        rv_plant = '1000'.
      WHEN 'PLANT2_100'.
        rv_plant = '2000'.
      WHEN 'PLANT3_100'.
        rv_plant = '3000'.
      WHEN OTHERS.
        " No specific plant mapping — caller handles INITIAL return
        CLEAR rv_plant.
    ENDCASE.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Filter E1MARCM (Plant Data) segments
*&---------------------------------------------------------------------*
  METHOD filter_plant_data.

    DATA: lv_segment_plant TYPE werks_d.

    " E1MARCM segment structure:
    " Position 3-6 (4 characters) = WERKS (Plant code)
    LOOP AT ct_idoc_data ASSIGNING FIELD-SYMBOL(<fs_idoc>)
      WHERE segnam = 'E1MARCM'.

      " Extract plant from segment data
      lv_segment_plant = <fs_idoc>-sdata+3(4).

      " Remove segments that don't belong to target plant
      IF lv_segment_plant <> iv_plant.
        DELETE ct_idoc_data INDEX sy-tabix.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Filter E1MBEWM (Valuation/Accounting) segments
*&---------------------------------------------------------------------*
  METHOD filter_accounting_data.

    DATA: lv_valuation_area TYPE bwkey.

    " E1MBEWM segment structure:
    " Position 3-6 (4 characters) = BWKEY (Valuation Area)
    LOOP AT ct_idoc_data ASSIGNING FIELD-SYMBOL(<fs_idoc>)
      WHERE segnam = 'E1MBEWM'.

      " Extract valuation area from segment data
      lv_valuation_area = <fs_idoc>-sdata+3(4).

      " Remove segments that don't belong to target plant
      IF lv_valuation_area <> iv_plant.
        DELETE ct_idoc_data INDEX sy-tabix.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

*&---------------------------------------------------------------------*
*& Add custom segments (Z-segments) if needed
*&---------------------------------------------------------------------*
  METHOD add_custom_segments.

    DATA: ls_custom_segment TYPE edidd.

    CASE iv_receiver_ls.
      WHEN 'PLANT1_100'.
        " Add custom segment for Plant 1
        ls_custom_segment-segnam = 'Z1CUSTOM'.
        ls_custom_segment-sdata  = 'PLANT1_SPECIFIC_DATA'.
        APPEND ls_custom_segment TO ct_idoc_data.

      WHEN 'PLANT2_100'.
        " Add custom segment for Plant 2
        ls_custom_segment-segnam = 'Z1CUSTOM'.
        ls_custom_segment-sdata  = 'PLANT2_SPECIFIC_DATA'.
        APPEND ls_custom_segment TO ct_idoc_data.

      WHEN 'PLANT3_100'.
        " Add custom segment for Plant 3
        ls_custom_segment-segnam = 'Z1CUSTOM'.
        ls_custom_segment-sdata  = 'PLANT3_SPECIFIC_DATA'.
        APPEND ls_custom_segment TO ct_idoc_data.
      WHEN OTHERS.
        " No custom segments for other receivers
    ENDCASE.

  ENDMETHOD.

ENDCLASS.
