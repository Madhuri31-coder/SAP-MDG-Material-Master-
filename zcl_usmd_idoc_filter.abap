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
*&   USMD_IDOC_FILTER intercepts the IDOC before dispatch and allows
*&   us to strip out irrelevant segments. This is the correct approach
*&   because:
*&     (a) It keeps IDOCs lean — smaller payloads, faster processing
*&     (b) It prevents receiving systems from processing data for plants
*&         they don't own, which would cause posting errors
*&     (c) It is the SAP-recommended pattern for multi-system MDG
*&         landscapes (see SAP Note 1849378)
*&
*& WHY FILTER E1MARCM AND E1MBEWM SEPARATELY?
*&   MATMAS05 IDOC structure separates plant data (E1MARCM) from
*&   valuation/accounting data (E1MBEWM). Both are plant-specific
*&   but stored in different segments. Filtering only E1MARCM would
*&   leave orphaned E1MBEWM segments which cause application errors
*&   (status 51) at the receiving system.
*&
*& WHY HARDCODED PLANT MAPPING IN get_plant_for_receiver?
*&   This portfolio implementation uses a CASE statement for clarity
*&   and readability. In a production system, the mapping would be
*&   maintained in a custom configuration table (e.g. ZMDG_LS_PLANT)
*&   so new plants/systems can be added without code changes or
*&   transports. The comment in the method makes this explicit.
*&
*& WHY ADD CUSTOM Z-SEGMENTS?
*&   Some receiving plants require non-standard data that doesn't
*&   exist in standard MATMAS segments (e.g. local tax codes, custom
*&   classification attributes). Z-segments allow this without
*&   modifying the standard IDOC type — the receiving system's inbound
*&   processing BAdI reads and handles these custom segments.
*&
*& IDOC SEGMENT OFFSET REFERENCE (MATMAS05):
*&   E1MARCM: sdata+0(3) = segment counter, sdata+3(4) = WERKS
*&   E1MBEWM: sdata+0(3) = segment counter, sdata+3(4) = BWKEY
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
*&
*& DESIGN NOTE: The method returns rv_filter_applied = false when
*& no plant mapping exists for the receiver. This tells the MDG
*& framework to send the unfiltered IDOC — a safe default for
*& receivers that receive all plants (e.g. a central reporting hub).
*& Returning false is preferable to raising an exception, which
*& would block the entire distribution run.
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
*&
*& DESIGN NOTE: Logical system names follow the convention
*& <PLANT_ID>_<CLIENT>. This mapping table would be externalised
*& to a custom Z-table in production (e.g. ZMDG_LS_PLANT) with
*& entries maintained via SM30, eliminating the need for code
*& changes when new plant systems are added to the landscape.
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
*&
*& DESIGN NOTE: E1MARCM segments hold plant-level material data
*& (MRP, purchasing, storage, etc.). Each segment in the IDOC
*& corresponds to one plant. We use offset-based field extraction
*& (sdata+3(4)) because E1MARCM is a flat character segment —
*& this is standard IDOC processing technique in classic ABAP.
*&
*& We loop and delete with sy-tabix. The FIELD-SYMBOL assignment
*& ensures we are working on the actual table row, not a copy.
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
*&
*& DESIGN NOTE: E1MBEWM holds material valuation data per valuation
*& area (BWKEY). In standard SAP configuration, valuation area equals
*& plant (company-code-level valuation is less common). We filter
*& by BWKEY = plant code, which covers the majority of real-world
*& system landscapes. For company-code-level valuation, this method
*& would need enhancement to map plant -> company code -> BWKEY.
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
*&
*& DESIGN NOTE: Z-segments carry receiver-specific metadata that
*& has no home in standard MATMAS05 segments. Examples include:
*&   - Local plant tax classification codes
*&   - Custom storage location defaults
*&   - ERP-to-WMS field mappings
*&
*& The receiving system's inbound processing BAdI (or a custom
*& function module mapped in WE57) reads these Z-segments and
*& posts the data to custom Z-tables or enhancement fields.
*&
*& Segment name Z1CUSTOM must be defined in WE31 and added to
*& the MATMAS05 extension MATMAS05E via WE30 before this works.
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

      WHEN OTHERS.
        " No custom segments for other receivers
    ENDCASE.

  ENDMETHOD.

ENDCLASS.
