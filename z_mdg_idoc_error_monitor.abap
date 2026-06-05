*&---------------------------------------------------------------------*
*& Report: Z_MDG_IDOC_ERROR_MONITOR
*& Purpose: Monitor and reprocess failed MDG Material IDOCs
*&---------------------------------------------------------------------*
*&
*& DESIGN WALKTHROUGH
*& ==================
*& WHY THIS REPORT EXISTS?
*&   IDOC distribution is asynchronous. After MDG activates a material
*&   change, the MATMAS05 IDOCs are dispatched to receiving systems via
*&   ALE. Network issues, system downtime, or data errors at the
*&   receiving end can cause IDOCs to fail silently — the MDG change
*&   request shows "Activated" but the plant system never received the
*&   update.
*&
*&   Standard SAP transaction WE05 shows IDOC errors but requires
*&   manual navigation per IDOC. This report provides:
*&     (a) Aggregated error visibility across all MDG IDOCs in a
*&         date range — one screen, full picture
*&     (b) Automated reprocessing for recoverable technical errors
*&         (status 64, 68) without manual intervention
*&     (c) Email alerting so the support team is proactively notified
*&         rather than discovering errors from business complaints
*&
*&
*&---------------------------------------------------------------------*
REPORT z_mdg_idoc_error_monitor.

*----------------------------------------------------------------------*
* Type Definitions
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_error_idoc,
         docnum  TYPE edi_docnum,
         status  TYPE edi_status,
         credat  TYPE edi_credat,
         cretim  TYPE edi_cretim,
         mestyp  TYPE edi_mestyp,
         rcvprn  TYPE edi_rcvprn,
         sndprn  TYPE edi_sndprn,
         matnr   TYPE matnr,
         statxt  TYPE edist,
         tabname TYPE edi_tabnam,
       END OF ty_error_idoc.

*----------------------------------------------------------------------*
* Data Declarations
*----------------------------------------------------------------------*
DATA: gt_error_idocs TYPE TABLE OF ty_error_idoc,
      gs_error_idoc  TYPE ty_error_idoc,
      gv_count       TYPE i,
      gv_reprocessed TYPE i,
      gv_failed      TYPE i.

*----------------------------------------------------------------------*
* Selection Screen
*
* DESIGN NOTE: Three blocks group related parameters logically.
* Block 1 (Date) and Block 2 (IDOC type) are filter criteria.
* Block 3 (Processing) controls what actions the report takes.
* Separating filters from actions makes the screen self-documenting
* and reduces user errors from misunderstanding checkboxes.
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_datefr TYPE sydatum DEFAULT sy-datum OBLIGATORY,
              p_dateto TYPE sydatum DEFAULT sy-datum OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS: p_msgty  TYPE edi_mestyp  DEFAULT 'MATMAS' OBLIGATORY,
              p_idocty TYPE edi_idoctyp DEFAULT 'MATMAS05'.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
  PARAMETERS: p_repro  AS CHECKBOX DEFAULT 'X',
              p_detail AS CHECKBOX,
              p_email  AS CHECKBOX.
  PARAMETERS: p_mailto TYPE ad_smtpadr DEFAULT 'mdg-support@company.com'.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* Initialization
*----------------------------------------------------------------------*
INITIALIZATION.
  " Default to last 7 days — covers typical weekly monitoring window
  " Most IDOC errors surface within 24-48h; 7 days catches stragglers
  p_datefr = sy-datum - 7.
  p_dateto = sy-datum.

*----------------------------------------------------------------------*
* Main Processing
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM fetch_error_idocs.
  PERFORM display_error_summary.

  IF p_detail = abap_true.
    PERFORM display_error_details.
  ENDIF.

  IF p_repro = abap_true.
    PERFORM reprocess_idocs.
    PERFORM display_reprocess_results.
  ENDIF.

  IF p_email = abap_true.
    PERFORM send_error_notification.
  ENDIF.

*----------------------------------------------------------------------*
* Fetch Error IDOCs
*
* DESIGN NOTE: We join EDIDC (control) → EDIDS (status text) →
* EDID4 (segment data) in separate SELECTs rather than a single
* join. Reason: EDID4 can have thousands of rows per IDOC and a
* join would create a cartesian explosion. The loop with targeted
* single selects is more efficient for typical error volumes
* (usually < 100 IDOCs per monitoring run).
*
* Material number extraction: E1MARAM segment holds the basic data
* header. MATNR starts at offset 3 (after 3-char segment counter)
* and is 18 characters. We strip leading zeros with SHIFT...LEFT
* DELETING LEADING '0' to match display format in MM03.
*----------------------------------------------------------------------*
FORM fetch_error_idocs.

  DATA: lt_edidc TYPE TABLE OF edidc,
        ls_edidc TYPE edidc.

  " Select failed IDOCs — status 51/64/68 only
  SELECT docnum status credat cretim mestyp rcvprn sndprn tabnam
    FROM edidc
    INTO CORRESPONDING FIELDS OF TABLE lt_edidc
    WHERE mestyp = p_msgty
      AND idoctp = p_idocty
      AND credat BETWEEN p_datefr AND p_dateto
      AND status IN ('51', '64', '68')
    ORDER BY credat DESCENDING, cretim DESCENDING.

  LOOP AT lt_edidc INTO ls_edidc.

    CLEAR gs_error_idoc.
    MOVE-CORRESPONDING ls_edidc TO gs_error_idoc.

    " Get the most recent status text from EDIDS
    " ORDER BY countr DESCENDING ensures we get the latest message,
    " not the first one (status can change multiple times)
    SELECT SINGLE statxt
      FROM edids
      INTO gs_error_idoc-statxt
      WHERE docnum = ls_edidc-docnum
      ORDER BY countr DESCENDING.

    " Extract material number from E1MARAM segment payload
    SELECT SINGLE sdata
      FROM edid4
      INTO @DATA(lv_sdata)
      WHERE docnum = @ls_edidc-docnum
        AND segnam = 'E1MARAM'.

    IF sy-subrc = 0.
      gs_error_idoc-matnr = lv_sdata+3(18).
      SHIFT gs_error_idoc-matnr LEFT DELETING LEADING '0'.
    ENDIF.

    APPEND gs_error_idoc TO gt_error_idocs.

  ENDLOOP.

  gv_count = lines( gt_error_idocs ).

ENDFORM.

*----------------------------------------------------------------------*
* Display Error Summary
*----------------------------------------------------------------------*
FORM display_error_summary.

  DATA: lv_status51 TYPE i,
        lv_status64 TYPE i,
        lv_status68 TYPE i.

  LOOP AT gt_error_idocs INTO gs_error_idoc.
    CASE gs_error_idoc-status.
      WHEN '51'. ADD 1 TO lv_status51.
      WHEN '64'. ADD 1 TO lv_status64.
      WHEN '68'. ADD 1 TO lv_status68.
    ENDCASE.
  ENDLOOP.

  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: / '   MDG IDOC ERROR MONITORING REPORT'.
  WRITE: / '═══════════════════════════════════════════════════════════'.
  SKIP 1.
  WRITE: / 'Date Range  :', p_datefr, '-', p_dateto.
  WRITE: / 'Msg Type    :', p_msgty.
  WRITE: / 'IDOC Type   :', p_idocty.
  SKIP 1.
  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'SUMMARY'.
  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'Total Errors                    :', gv_count.
  WRITE: / ' Status 51 (Application Error)  :', lv_status51 COLOR COL_NEGATIVE.
  WRITE: / ' Status 64 (Ready for transfer) :', lv_status64 COLOR COL_TOTAL.
  WRITE: / ' Status 68 (ALE Service Error)  :', lv_status68 COLOR COL_TOTAL.
  SKIP 1.

ENDFORM.

*----------------------------------------------------------------------*
* Display Detailed Error List
*----------------------------------------------------------------------*
FORM display_error_details.

  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'DETAILED ERROR LIST'.
  WRITE: / '───────────────────────────────────────────────────────────'.
  SKIP 1.
  WRITE: / 'IDOC Number', 20 'Sts', 25 'Material',
            40 'Receiver', 55 'Date', 66 'Time', 76 'Error Description'.
  WRITE: / sy-uline.

  LOOP AT gt_error_idocs INTO gs_error_idoc.
    WRITE: / gs_error_idoc-docnum,
             20 gs_error_idoc-status COLOR COL_NEGATIVE,
             25 gs_error_idoc-matnr,
             40 gs_error_idoc-rcvprn,
             55 gs_error_idoc-credat,
             66 gs_error_idoc-cretim,
             76 gs_error_idoc-statxt(50).
  ENDLOOP.

  SKIP 1.

ENDFORM.

FORM reprocess_idocs.

  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'REPROCESSING FAILED IDOCS'.
  WRITE: / '───────────────────────────────────────────────────────────'.
  SKIP 1.

  LOOP AT gt_error_idocs INTO gs_error_idoc.

    WRITE: / 'Processing IDOC:', gs_error_idoc-docnum, '...'.

    IF gs_error_idoc-status = '64' OR gs_error_idoc-status = '68'.

      CALL FUNCTION 'EDI_DOCUMENT_REPROCESS_DIRECT'
        EXPORTING
          document_number       = gs_error_idoc-docnum
        EXCEPTIONS
          document_number_invalid = 1
          OTHERS                  = 2.

      IF sy-subrc = 0.
        WRITE: ' SUCCESS', icon_led_green AS ICON.
        ADD 1 TO gv_reprocessed.
      ELSE.
        WRITE: ' FAILED', icon_led_red AS ICON.
        ADD 1 TO gv_failed.
      ENDIF.

    ELSE.
      " Status 51 — data error, needs manual correction before retry
      WRITE: ' SKIPPED (status 51 - requires manual correction)',
             icon_led_yellow AS ICON.
    ENDIF.

  ENDLOOP.

  SKIP 1.

ENDFORM.

*----------------------------------------------------------------------*
* Display Reprocessing Results
*----------------------------------------------------------------------*
FORM display_reprocess_results.

  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'REPROCESSING RESULTS'.
  WRITE: / '───────────────────────────────────────────────────────────'.
  WRITE: / 'Successfully Reprocessed :', gv_reprocessed COLOR COL_POSITIVE.
  WRITE: / 'Failed to Reprocess      :', gv_failed      COLOR COL_NEGATIVE.
  SKIP 1.

ENDFORM.

*----------------------------------------------------------------------*
* Send Email Notification
----------------------------------*
FORM send_error_notification.

  DATA: lt_mail_body TYPE TABLE OF soli,
        ls_mail_body TYPE soli,
        lv_subject   TYPE so_obj_des.

  CONCATENATE 'MDG IDOC Alert:' gv_count 'errors found on' sy-datum
    INTO lv_subject SEPARATED BY space.

  ls_mail_body = 'MDG IDOC Error Monitoring Report'.
  APPEND ls_mail_body TO lt_mail_body.
  APPEND INITIAL LINE TO lt_mail_body.
  ls_mail_body = '───────────────────────────────────────'.
  APPEND ls_mail_body TO lt_mail_body.
  CONCATENATE 'Total Errors Found : ' gv_count INTO ls_mail_body.
  APPEND ls_mail_body TO lt_mail_body.
  CONCATENATE 'Date Range         : ' p_datefr ' - ' p_dateto
    INTO ls_mail_body.
  APPEND ls_mail_body TO lt_mail_body.
  APPEND INITIAL LINE TO lt_mail_body.
  ls_mail_body = 'Please review errors in transaction WE02 / WE05.'.
  APPEND ls_mail_body TO lt_mail_body.
  ls_mail_body = 'Status 64/68 errors have been auto-reprocessed.'.
  APPEND ls_mail_body TO lt_mail_body.
  ls_mail_body = 'Status 51 errors require manual investigation.'.
  APPEND ls_mail_body TO lt_mail_body.

  CALL FUNCTION 'SO_NEW_DOCUMENT_ATT_SEND_API1'
    EXPORTING
      document_data = VALUE sodocchgi1(
                        obj_name  = 'IDOC_ERROR'
                        obj_descr = lv_subject )
      commit_work   = 'X'
    TABLES
      object_content = lt_mail_body
      receivers      = VALUE somlreci1_tab(
                         ( receiver = p_mailto
                           rec_type = 'U' ) )
    EXCEPTIONS
      too_many_receivers = 1
      document_not_sent  = 2
      OTHERS             = 3.

  IF sy-subrc = 0.
    WRITE: / 'Email notification sent to:', p_mailto, icon_led_green AS ICON.
  ELSE.
    WRITE: / 'Email notification failed - check SCOT configuration',
             icon_led_red AS ICON.
  ENDIF.

ENDFORM.

