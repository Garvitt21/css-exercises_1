/* =====================================================================
   Balance sheet (as-at today, -3 months, -6 months)
   Optimised for DuckDB: every parquet source is scanned once and reused.
     - balance_sheet_raw : 1 scan (was ~24)
     - glentry + glaccountaq : 1 scan, pre-aggregated per (account, as-at)
     - vendor ledger chain : built once (vendorTotals), reused by 5 consumers
     - dead CTEs removed (ECL chain, adj_filtered, unsecured loans, etc.)
   Block comments (/* */) are used on purpose so the query survives
   being collapsed to a single line.
   ===================================================================== */
WITH tillPostingDate AS (
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' as DATE) as agedAsOf
    UNION ALL
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' AS DATE) - INTERVAL 3 MONTHS
    UNION ALL
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' AS DATE) - INTERVAL 6 MONTHS
),

/* ── Account mapping: ONE scan of balance_sheet_raw ─────────────────── */
bs AS MATERIALIZED (
    SELECT "No."                    AS accno,
           "sub note"               AS sub_note_raw,   /* untrimmed, some filters depend on it */
           trim("sub note")         AS sub_note,
           "Sub sub note"           AS sub_sub_note,
           trim("Face ")            AS face
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/glaccountaq/balance_sheet_raw.xlsx.parquet'
),
ppe_accounts                  AS (SELECT accno FROM bs WHERE sub_sub_note = 'PPE'),
cwp_accounts                  AS (SELECT accno FROM bs WHERE sub_sub_note LIKE 'Capital%'),
rtu_accounts                  AS (SELECT accno FROM bs WHERE sub_sub_note LIKE 'Right%'),
intangbile_accounts           AS (SELECT accno FROM bs WHERE sub_sub_note LIKE 'Intangible%'),
non_current_accounts          AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Investment in Govt. bonds', 'Investment in Subsidiary', 'Investment in MF')),
non_current_lease_accounts    AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Lease Liability - INDAS')),
other_accounts                AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Securities Deposits')),
inventory_accounts            AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Finished goods', 'Raw materials')),
long_term_borrowing_accounts  AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Secured Term loans from Bank - Long term', 'Loans from directors and related Parties')),
loans_accounts                AS (SELECT DISTINCT accno FROM bs WHERE sub_note_raw IN ('Advance to Staff', ' Advance to Subsidiary')),
trade_accounts                AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Allowance for expected credit loss')),
cash_accounts                 AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Balances with Banks in current accounts', 'Balances with Banks in Cash Credit accounts', 'Cash on hand')),
other_cash_accounts           AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Fixed Deposits (held as Margin Money against BG/LC and Short TL)')),
current_investment_accounts   AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Current Investment')),
other_current_accounts        AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Other Receivable', 'Preliminery-Preoperative Expense', 'Prepaid Expenses', 'Balance with Statutory/ Govt. Authorities', 'Subsidy Receivable')),
equity_share_accounts         AS (SELECT DISTINCT accno FROM bs WHERE face IN ('Equity Share Capital')),
other_equity_accounts         AS (SELECT DISTINCT accno FROM bs WHERE face IN ('Other Equity')),
short_term_accounts           AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Current Gratuity Provision', 'Dividend payable')),
income_tax_accounts           AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Provisions for Income Tax')),
long_term_accounts            AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Provision for O & M', 'Gratuity Provision', 'Provision For CSR')),
deferred_tax_accounts         AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Deferred Tax Liabilities (Net)')),
short_term_borrowing_accounts AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Secured cash credit', 'Loans from Financial institution')),
other_current_liabilites_accounts AS (SELECT DISTINCT accno FROM bs WHERE sub_note IN ('Statutory liabilities')),
micro_trade_accounts AS (
    SELECT '112800' AS accno UNION ALL SELECT '121000' UNION ALL SELECT '124130'
),

/* ── GL ledger: ONE scan, pre-aggregated to (account, as-at) ────────── */
gl_base AS MATERIALIZED (
    SELECT gla.No                 AS No,
           tp.agedAsOf::Date      AS asat,
           sum(gle.amount)        AS amount
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/glentry/glentry.parquet' gle
    LEFT JOIN '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/glaccountaq/glaccountaq.parquet' gla ON gla.NO = gle.glAccountNo
    CROSS JOIN tillPostingDate tp
    WHERE gle.postingDate::Date <= tp.agedAsOf
      AND Income_Balance = 'Balance Sheet'
      AND 1=1                     /* branch filter hook */
    GROUP BY gla.No, tp.agedAsOf::Date
),

/* ── Lease / loan schedules ─────────────────────────────────────────── */
current_lease_values_raw AS (
    SELECT '(ii) Lease liabilities' AS non_current_assets, '19' AS noteno,
           round(sum(Repayment), 5) AS amount, 33 AS srno,
           'Current liabilities' AS subheader, tillPostingDate.agedAsOf::Date AS asat
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/glaccountaq/lease_liability.xlsx.parquet'
    CROSS JOIN tillPostingDate
    WHERE CAST(strftime('%Y', tillPostingDate.agedAsOf::Date) AS INTEGER) + 1 = CAST(strftime('%Y', Quarter::Date) AS INTEGER)
    GROUP BY non_current_assets, noteno, asat
),
secured_loan_master AS (
    SELECT Date::Date AS loan_date, Principal AS principal, "GL CODE" AS gl_code,
           min(Date::Date) OVER (PARTITION BY "GL CODE") AS loan_first_date
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/glaccountaq/loan_master_secured.xlsx.parquet'
),
secured_loan_next12_values_raw AS (
    SELECT -round(sum(slm.principal), 5) AS amount, tp.agedAsOf::Date AS asat
    FROM (
        SELECT agedAsOf, agedAsOf::Date AS aged_date,
               (date_trunc('month', agedAsOf::Date) + INTERVAL 1 MONTH)::Date AS window_start
        FROM tillPostingDate
    ) tp
    CROSS JOIN secured_loan_master slm
    WHERE slm.loan_first_date <= tp.aged_date   -- account qualifies as of agedAsOf exactly
      AND slm.loan_date >= tp.window_start      -- principal summed from next month start
      AND slm.loan_date <= tp.window_start + INTERVAL 12 MONTHS
    GROUP BY tp.agedAsOf
),

/* ══ VENDOR CHAIN (built once) ═══════════════════════════════════════ */
vendorMachineryPostingGroupsToConsider AS (
    SELECT Code
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/msd_finance/vle_posting_groups.xlsx.parquet'
    WHERE Remark = 'Consider'
      AND 1=1                     /* filter hook */
),
vleDetails AS (
    SELECT SUM(amountLCY) AS amountLCY, SUM(amount) AS amount, vendorLedgerEntryNo, currencyCode,
           tillpostingdate.agedAsOf::Date AS asat
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/detailed_vendor_ledger/detailed_vendor_ledger.parquet'
    CROSS JOIN tillpostingdate
    WHERE entryType <> 'Initial Entry'
      AND CAST(postingDate AS date) <= tillPostingDate.agedAsOf::Date
    GROUP BY vendorLedgerEntryNo, currencyCode, asat
),
allDetails AS (
    SELECT
        CAST(v.postingDate AS date)                AS postingDate,
        v.vendorNo                                 AS customerNum,
        vm.name                                    AS customerName,
        v.entryNo                                  AS entryNum,
        -(vd.amountLCY::numeric)                   AS cdAmount,
        -(orgAmt.orgAmount::numeric)               AS orgAmount,
        -(orgAmt.orgAmountOrgCur::numeric)         AS orgAmountOrgCur,
        v.documentNo                               AS docNo,
        CAST(v.dueDate AS date)                    AS dueDate,
        tillPostingDate.agedAsOf::DATE - dueDate::DATE AS DueSince,
        CAST(v.documentDate AS date)               AS docDate,
        v.documentType                             AS documentType,
        v.externalDocumentNo                       AS externalDocNo,
        CASE WHEN docNo LIKE 'PUR%' OR docNo LIKE 'PIM%' THEN 'Invoice'
             WHEN docNo LIKE 'BP%'  OR docNo LIKE 'CP%'  THEN 'Payment'
             WHEN docNo LIKE 'BR%'                       THEN 'Refund'
             WHEN docNo LIKE 'PR%'                       THEN 'Credit Memo'
             ELSE 'Other Entries' END              AS _documentType,
        sctn.State                                 AS state,
        COALESCE(Stage3, 'OTHERS')                 AS responsiblePerson,
        CASE WHEN v.invoiceReceivedDate <> '0001-01-01'
             THEN TRY_CAST(v.invoiceReceivedDate AS date) ELSE NULL END AS invRecDate,
        vm.vendorPostingGroup                      AS vendorPostiongGroup,
        vm.genBusPostingGroup                      AS genBusinessPostingGroup,
        v.Global_Dimension_1_Code                  AS Bcode,
        tillpostingdate.agedAsOf::Date             AS asat
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/vle/vle.parquet' v
    LEFT JOIN '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/vendor_master_/vendor_master_.parquet' vm ON vm.no = v.vendorNo
    LEFT JOIN '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/msd_finance/state_code_to_name.xlsx.parquet' sctn ON sctn.stateCode = v.buyerStateCode
    LEFT JOIN (
        SELECT vendorLedgerEntryNo AS vlen, amountLCY AS orgAmount, amount AS orgAmountOrgCur
        FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/detailed_vendor_ledger/detailed_vendor_ledger.parquet'
        WHERE entryType = 'Initial Entry'
    ) orgAmt ON orgAmt.vlen = v.entryNo
    CROSS JOIN tillpostingdate
    LEFT JOIN vleDetails vd ON v.entryNo = vd.vendorLedgerEntryNo AND vd.asat = tillpostingdate.agedAsOf::Date
    WHERE v.Reversed = False
      AND postingDate::DATE <= tillPostingDate.agedAsOf::Date
      AND vm.vendorPostingGroup IN (SELECT * FROM vendorMachineryPostingGroupsToConsider)
      AND 1=1                     /* filter hook */
      AND v.vendorNo NOT IN ('V00005', 'V00006', 'V01289', 'V01789', 'V01905', 'V01733')
),
entryWiseDetails AS (
    SELECT postingDate, customerNum, customerName, entryNum, orgAmount, orgAmountOrgCur,
           IFNULL(SUM(cdAmount), 0) AS settleAmount,
           orgAmount + settleAmount AS AR,
           docNo, dueDate, DueSince, docDate, documentType, _documentType,
           responsiblePerson, state, externalDocNo, invRecDate,
           vendorPostiongGroup, genBusinessPostingGroup, Bcode, asat
    FROM allDetails
    GROUP BY postingDate, customerNum, customerName, entryNum, orgAmount, orgAmountOrgCur,
             docNo, dueDate, DueSince, docDate, documentType, _documentType,
             responsiblePerson, state, externalDocNo, invRecDate,
             vendorPostiongGroup, genBusinessPostingGroup, Bcode, asat
),
unSettledEntries AS (
    SELECT customerNum, customerName, AR, responsiblePerson, vendorPostiongGroup, asat
    FROM entryWiseDetails
    WHERE AR <> 0
      AND 1=1                     /* filter hook */
),
vendorWiseDetails AS (
    SELECT customerNum, customerName, SUM(AR) AS AR, responsiblePerson, vendorPostiongGroup, asat
    FROM unSettledEntries
    GROUP BY customerNum, customerName, responsiblePerson, vendorPostiongGroup, asat
),
/* One shared table replaces the 5 copies of the x/y subquery.
   The |AR| >= 0.5 filter is applied BEFORE the window, exactly as before. */
vendorTotals AS MATERIALIZED (
    SELECT *, SUM(AR) OVER (PARTITION BY customerNum, asat) AS customerTotal
    FROM vendorWiseDetails
    WHERE AR >= 0.5 OR AR <= -0.5
),
machineryVendorAdvanceResult AS (
    SELECT -sum(AR) AS amount, asat
    FROM vendorTotals
    WHERE customerTotal < 0
      AND vendorPostiongGroup IN ('DOMESTICS MACHINARY', 'IMPORT MACHINERY', 'CONSUMABLE', 'IMPORT CONSUMABLE',
                                  'SERVICES IMPORT', 'EPC RM', 'IMPORT RM', 'MODULE RM', 'SERVICES')
    GROUP BY asat
),
machineryVendorPayableResult AS (
    SELECT -sum(AR) AS amount, asat, vendorPostiongGroup
    FROM vendorTotals
    WHERE customerTotal > 0
    GROUP BY asat, vendorPostiongGroup
),
machineryVendornetResult AS (
    SELECT -sum(AR) AS amount, asat, vendorPostiongGroup
    FROM vendorTotals
    GROUP BY asat, vendorPostiongGroup
),
vendor_msme AS MATERIALIZED (
    SELECT TRIM(no) AS vendorno, TRIM(MSME_Type) AS msme_type
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/vendor_master_/vendor_master_.parquet'
),
msme_data AS (SELECT vendorno FROM vendor_msme WHERE msme_type <> ''),
non_msme  AS (SELECT vendorno FROM vendor_msme WHERE msme_type = ''),

/* ══ CUSTOMER ADVANCE / RECEIVABLE CHAIN (built once) ════════════════ */
postingGroupsToConsider AS (
    SELECT Code
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/msd_finance/cle_posting_group_code.xlsx.parquet'
    WHERE Remark = 'Consider'
      AND 1=1                     /* filter hook */
),
cleDetails AS (
    SELECT d.custLedgerEntryNo, d.amountLCY, tp.agedAsOf::Date AS asat
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/detailed_cust_ledger/detailed_cust_ledger.parquet' d
    CROSS JOIN tillPostingDate tp
    WHERE d.entryType <> 'Initial Entry'
      AND CAST(d.postingDate AS date) <= tp.agedAsOf::Date
),
allDetails_adv AS (
    SELECT CAST(c.Posting_Date AS date)            AS postingDate,
           c.Customer_No_                          AS customerNum,
           c.entryNo                               AS entryNum,
           cd.amountLCY::numeric                   AS cdAmount,
           c.originalAmtLCY                        AS orgAmount,
           c.documentNo                            AS docNo,
           CAST(c.dueDate AS date)                 AS dueDate,
           tillPostingDate.agedAsOf::Date - dueDate::DATE AS DueSince,
           CAST(c.documentDate AS date)            AS docDate,
           COALESCE(cm.name, '')                   AS customerName,
           c.Document_Type                         AS documentType,
           COALESCE(cm.customerPostingGroup, 'SOLEX') AS customerPostingGroup,
           bm.Address                              AS branchAddress,
           c.globalDimension1Code                  AS branchCode,
           IFNULL(cm.Stage_4, '')                  AS responsiblePerson,
           tillPostingDate.agedAsOf::Date          AS asat
    FROM '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/cle/cle.parquet' c
    LEFT JOIN '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/customer_master/customer_master.parquet' cm ON cm.no = c.Customer_No_
    CROSS JOIN tillPostingDate
    LEFT JOIN cleDetails cd ON c.entryNo = cd.custLedgerEntryNo AND cd.asat = tillPostingDate.agedAsOf::Date
    LEFT JOIN '/var/www/html/rapidBuild/backend-python/rapidBuild/datasets/parquet//34/msd_finance/branch_map.xlsx.parquet' bm ON c.globalDimension1Code = bm.Branch
    WHERE c.Reversed = False
      AND CAST(c.Posting_Date AS date) <= tillPostingDate.agedAsOf::Date
      AND c.customerPostingGroup IN (SELECT * FROM postingGroupsToConsider)
      AND 1=1                     /* filter hook */
),
entryWiseDetails_adv AS (
    SELECT postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
           IFNULL(SUM(cdAmount), 0) AS settleAmount,
           orgAmount + settleAmount AS AR,
           docNo, dueDate, DueSince, docDate, customerName, documentType,
           branchAddress, branchCode, responsiblePerson, asat
    FROM allDetails_adv
    GROUP BY postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
             docNo, dueDate, DueSince, docDate, customerName, documentType,
             branchAddress, branchCode, responsiblePerson, asat
),
/* Per customer + posting group; customerTotal spans all of the customer's rows, as before. */
custTotals_adv AS MATERIALIZED (
    SELECT customerNum, customerPostingGroup, asat,
           SUM(AR)                                              AS AR,
           SUM(SUM(AR)) OVER (PARTITION BY customerNum, asat)   AS customerTotal
    FROM entryWiseDetails_adv
    WHERE AR <> 0
    GROUP BY customerNum, customerPostingGroup, asat
),
query1_result AS (
    SELECT -sum(AR) AS amount, asat
    FROM custTotals_adv
    WHERE customerTotal < 0
      AND lower(customerPostingGroup) IN ('epc commercial', 'epc govt project', 'epc ground mounted', 'epc roof top',
                                          'module domestic', 'module foreign', 'epc scrap', 'suspense')
    GROUP BY asat
),
query2_result AS (
    SELECT round(COALESCE(sum(AR), 0), 5) AS amount, asat
    FROM custTotals_adv
    WHERE customerTotal > 0
      AND TRIM(customerPostingGroup) IN ('LC DOMESTIC', 'MODULE DOMESTIC', 'MODULE FOREIGN', 'MODULE JOB',
                                         'EPC GOVT PROJECT', 'EPC ROOF TOP', 'EPC COMMERCIAL',
                                         'EPC GROUND MOUNTED', 'EPC SCRAP', 'SUSPENSE')
    GROUP BY asat
),

/* ── _raw CTEs: all read the tiny pre-aggregated gl_base ────────────── */
ppe_value_raw AS (
    SELECT '(a) Property, Plant and Equipment' AS non_current_assets, '2(a)' AS noteno,
           round(sum(amount), 5) AS amount, 3 AS srno, 'Non Current Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM ppe_accounts)
    GROUP BY non_current_assets, noteno, asat
),
cwp_value_raw AS (
    SELECT '(b) Capital work-in-progress' AS non_current_assets, '2(b)' AS noteno,
           round(sum(amount), 5) AS amount, 4 AS srno, 'Non Current Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM cwp_accounts)
    GROUP BY non_current_assets, noteno, asat
),
rtu_value_raw AS (
    SELECT '(c) Right-of-use assets' AS non_current_assets, '2(c)' AS noteno,
           round(sum(amount), 5) AS amount, 5 AS srno, 'Non Current Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM rtu_accounts)
    GROUP BY non_current_assets, noteno, asat
),
intangbile_value_raw AS (
    SELECT '(ii) Other intangible assets' AS non_current_assets, '2(a)' AS noteno,
           round(sum(amount), 5) AS amount, 7 AS srno, '(e) Intangible Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM intangbile_accounts)
    GROUP BY non_current_assets, noteno, asat
),
non_current_values_raw AS (
    SELECT '(i) Non-current investments' AS non_current_assets, '3' AS noteno,
           round(sum(amount), 5) AS amount, 10 AS srno, '(f) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM non_current_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_values_raw AS (
    SELECT '(ii) Others' AS non_current_assets, '4' AS noteno,
           round(sum(amount), 5) AS amount, 11 AS srno, '(f) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM other_accounts)
    GROUP BY non_current_assets, noteno, asat
),
inventory_values_raw AS (
    SELECT '(a) Inventories' AS non_current_assets, '5' AS noteno,
           round(sum(amount), 5) AS amount, 13 AS srno, 'Current assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM inventory_accounts)
    GROUP BY non_current_assets, noteno, asat
),
trade_values_raw AS (
    SELECT '(ii) Trade and other receivables' AS non_current_assets, '7' AS noteno,
           round(sum(amount), 5) AS amount, '(b) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM trade_accounts)
    GROUP BY non_current_assets, noteno, asat
),
cash_values_raw AS (
    SELECT '(iii) Cash and cash equivalents' AS non_current_assets, '8' AS noteno,
           round(sum(amount), 5) AS amount, 17 AS srno, '(b) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM cash_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_cash_values_raw AS (
    SELECT '(iv) Bank balances other than Cash and cash equivalents' AS non_current_assets, '9' AS noteno,
           round(sum(amount), 5) AS amount, 18 AS srno, '(b) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM other_cash_accounts)
    GROUP BY non_current_assets, noteno, asat
),
current_investment_values_raw AS (
    SELECT '(i) Current investments' AS non_current_assets, '6' AS noteno,
           round(sum(amount), 5) AS amount, 15 AS srno, '(b) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM current_investment_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_current_values_raw AS (
    SELECT '(c) Other current assets' AS non_current_assets, '11' AS noteno,
           round(sum(amount), 5) AS amount, 20 AS srno, 'Current assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM other_current_accounts)
    GROUP BY non_current_assets, noteno, asat
),
equity_share_values_raw AS (
    SELECT 'Equity Share Capital' AS non_current_assets, '12' AS noteno,
           round(-sum(amount), 5) AS amount, 'Equity' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM equity_share_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_equity_values_raw AS (
    SELECT 'Other Equity' AS non_current_assets, '13' AS noteno,
           round(-sum(amount), 5) AS amount, 23 AS srno, 'Equity' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM other_equity_accounts)
    GROUP BY non_current_assets, noteno, asat
),
long_term_values_raw AS (
    SELECT '(b) Long-term provisions' AS non_current_assets, '16' AS noteno,
           round(-sum(amount), 5) AS amount, 28 AS srno, 'Non-current liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM long_term_accounts)
    GROUP BY non_current_assets, noteno, asat
),
deferred_tax_values_raw AS (
    SELECT '(c) Deferred tax liabilities (Net)' AS non_current_assets, '17' AS noteno,
           round(-sum(amount), 5) AS amount, 29 AS srno, 'Non-current liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM deferred_tax_accounts)
    GROUP BY non_current_assets, noteno, asat
),
income_tax_values_raw AS (
    SELECT '(c) Income tax liabilities (net)' AS non_current_assets, '23' AS noteno,
           round(-sum(amount), 5) AS amount, 39 AS srno, 'Current liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM income_tax_accounts)
    GROUP BY non_current_assets, noteno, asat
),
non_current_lease_values_raw AS (
    SELECT ncl.non_current_assets, ncl.noteno, round(ncl.amount - cl.amount, 5) AS amount, ncl.srno,
           'Non-current liabilities' AS subheader, ncl.asat
    FROM (
        SELECT '(ii) Lease liabilities' AS non_current_assets, '15' AS noteno,
               round(-sum(amount), 5) AS amount, 27 AS srno, asat
        FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM non_current_lease_accounts)
        GROUP BY non_current_assets, noteno, asat
    ) AS ncl
    JOIN current_lease_values_raw AS cl ON ncl.asat = cl.asat
),

/* ── _raw CTEs that also depend on the vendor / customer chains ─────── */
short_term_values_raw_base AS (
    SELECT '(c) Short-term provisions' AS non_current_assets, '22' AS noteno,
           round(-sum(amount), 5) AS amount, 38 AS srno, 'Current liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM short_term_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_short_term_provision AS (
    SELECT -sum(amount) AS amount, asat
    FROM machineryVendorPayableResult
    WHERE vendorPostiongGroup = 'PROVISION CREDITOR'
    GROUP BY asat
),
short_term_values_raw AS (
    SELECT lb.non_current_assets, lb.noteno,
           lb.amount + round(COALESCE(mva.amount, 0), 5) AS amount,
           lb.srno, lb.subheader, lb.asat
    FROM short_term_values_raw_base lb
    LEFT JOIN other_short_term_provision mva ON mva.asat = lb.asat
),
loans_values_raw_base AS (
    SELECT '(v) Loans and advances' AS non_current_assets, '10' AS noteno,
           round(sum(amount), 5) AS amount, 19 AS srno, '(b) Financial Assets' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM loans_accounts)
    GROUP BY non_current_assets, noteno, asat
),
loans_values_raw AS (
    SELECT lb.non_current_assets, lb.noteno,
           lb.amount + round(COALESCE(mva.amount, 0), 5) AS amount,
           lb.srno, lb.subheader, lb.asat
    FROM loans_values_raw_base lb
    LEFT JOIN machineryVendorAdvanceResult mva ON mva.asat = lb.asat
),
long_term_borrowing_values_raw_base AS (
    SELECT '(i) Long-term borrowings' AS non_current_assets, '14' AS noteno,
           round(-sum(amount), 5) AS amount, 26 AS srno, '(a) Financial Liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM long_term_borrowing_accounts)
    GROUP BY non_current_assets, noteno, asat
),
long_term_borrowing_values_raw AS (
    SELECT lb.non_current_assets, lb.noteno, lb.amount - COALESCE(sl.amount, 0) AS amount,
           lb.srno, lb.subheader, lb.asat
    FROM long_term_borrowing_values_raw_base lb
    LEFT JOIN secured_loan_next12_values_raw sl ON sl.asat = lb.asat
),
short_term_borrowing_values_raw_base AS (
    SELECT '(i) Short Term Borrowings' AS non_current_assets, '18' AS noteno,
           round(-sum(amount), 5) AS amount, 32 AS srno, '(a) Financial Liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM short_term_borrowing_accounts)
    GROUP BY non_current_assets, noteno, asat
),
short_term_borrowing_values_raw AS (
    SELECT sb.non_current_assets, sb.noteno, sb.amount + COALESCE(sl.amount, 0) AS amount,
           sb.srno, sb.subheader, sb.asat
    FROM short_term_borrowing_values_raw_base sb
    LEFT JOIN secured_loan_next12_values_raw sl ON sl.asat = sb.asat
),
micro_trade_values_raw_base AS (
    SELECT 'b) Total outstanding dues of other than micro enterprises and small enterprises' AS non_current_assets,
           '' AS noteno, round(-sum(amount), 5) AS amount, 36 AS srno,
           '(iii) Trade and other payables' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM micro_trade_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_current_liabilites_values_raw_base AS (
    SELECT '(b) Other current liabilities' AS non_current_assets, '21' AS noteno,
           round(-sum(amount), 5) AS amount, 37 AS srno, 'Current liabilities' AS subheader, asat
    FROM gl_base WHERE cast(No AS varchar) IN (SELECT DISTINCT cast(accno AS varchar) FROM other_current_liabilites_accounts)
    GROUP BY non_current_assets, noteno, asat
),
other_current_liabilites_payable AS (
    SELECT -sum(amount) AS amount, asat
    FROM machineryVendornetResult
    WHERE vendorPostiongGroup = 'EXPENSES'
    GROUP BY asat
),
creditors_for_capex AS (
    SELECT -sum(amount) AS amount, asat
    FROM machineryVendorPayableResult
    WHERE vendorPostiongGroup IN ('DOMESTICS MACHINARY', 'IMPORT MACHINERY')
    GROUP BY asat
),
other_current_liabilites_values_raw AS (
    SELECT ol.non_current_assets, ol.noteno,
           ol.amount + round(COALESCE(qr.amount, 0), 5)
                     + round(COALESCE(op.amount, 0), 5)
                     + round(COALESCE(cp.amount, 0), 5) AS amount,
           ol.srno, ol.subheader, ol.asat
    FROM other_current_liabilites_values_raw_base ol
    LEFT JOIN query1_result qr ON qr.asat = ol.asat
    LEFT JOIN other_current_liabilites_payable op ON ol.asat = op.asat
    LEFT JOIN creditors_for_capex cp ON ol.asat = cp.asat
),
other_trade_values_raw AS (
    SELECT 'a) Total outstanding dues of micro enterprises and small enterprises' AS non_current_assets,
           '' AS noteno, round(-sum(amount), 5) AS amount, 35 AS srno,
           '(iii) Trade and other payables' AS subheader, asat
    FROM (
        SELECT -sum(AR) AS amount, asat
        FROM vendorTotals
        WHERE customerTotal > 0
          AND customerNum IN (SELECT DISTINCT vendorno FROM msme_data)
          AND vendorPostiongGroup NOT IN ('EXPENSES', 'DOMESTICS MACHINARY', 'IMPORT MACHINARY', 'CONTRACT CREDITOR')
        GROUP BY asat
    )
    GROUP BY asat
),
micro_temp AS (
    SELECT sum(AR) AS amount, asat
    FROM vendorTotals
    WHERE customerTotal > 0
      AND customerNum IN (SELECT DISTINCT vendorno FROM non_msme)
      AND vendorPostiongGroup IN ('IMPORT RM', 'MODULE RM', 'EPC RM', 'SERVICES', 'LC FOREIGN', 'CONSUMABLE',
                                  'IMPORT CONSUMABLE', 'SERVICES IMPORT', 'CONTRACT CREDITOR')
    GROUP BY asat
),
micro_trade_values_raw AS (
    SELECT ol.non_current_assets, ol.noteno,
           ol.amount + round(COALESCE(mt.amount, 0), 5) AS amount,
           ol.srno, ol.subheader, ol.asat
    FROM micro_trade_values_raw_base ol
    LEFT JOIN micro_temp mt ON ol.asat = mt.asat
),

/* ── _value CTEs: per-as-at zero fallback ───────────────────────────── */
ppe_value AS (
    SELECT * FROM ppe_value_raw
    UNION ALL
    SELECT '(a) Property, Plant and Equipment', '2(a)', 0, 3, 'Non Current Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN ppe_value_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
cwp_value AS (
    SELECT * FROM cwp_value_raw
    UNION ALL
    SELECT '(b) Capital work-in-progress', '2(b)', 0, 4, 'Non Current Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN cwp_value_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
rtu_value AS (
    SELECT * FROM rtu_value_raw
    UNION ALL
    SELECT '(c) Right-of-use assets', '2(c)', 0, 5, 'Non Current Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN rtu_value_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
intangbile_value AS (
    SELECT * FROM intangbile_value_raw
    UNION ALL
    SELECT '(ii) Other intangible assets', '2(a)', 0, 7, '(e) Intangible Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN intangbile_value_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
non_current_values AS (
    SELECT * FROM non_current_values_raw
    UNION ALL
    SELECT '(i) Non-current investments', '3', 0, 10, '(f) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN non_current_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_values AS (
    SELECT * FROM other_values_raw
    UNION ALL
    SELECT '(ii) Others', '4', 0, 11, '(f) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
inventory_values AS (
    SELECT * FROM inventory_values_raw
    UNION ALL
    SELECT '(a) Inventories', '5', 0, 13, 'Current assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN inventory_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
/* trade_values carries the query2 (customer receivable) adjustment */
trade_values AS (
    SELECT t.non_current_assets, t.noteno, t.amount + COALESCE(q2.amount, 0) AS amount, t.subheader, t.asat
    FROM trade_values_raw t
    LEFT JOIN query2_result q2 ON t.asat = q2.asat
    UNION ALL
    SELECT '(ii) Trade and other receivables', '7', 0, '(b) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN trade_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
cash_values AS (
    SELECT * FROM cash_values_raw
    UNION ALL
    SELECT '(iii) Cash and cash equivalents', '8', 0, 17, '(b) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN cash_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_cash_values AS (
    SELECT * FROM other_cash_values_raw
    UNION ALL
    SELECT '(iv) Bank balances other than Cash and cash equivalents', '9', 0, 18, '(b) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_cash_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
current_investment_values AS (
    SELECT * FROM current_investment_values_raw
    UNION ALL
    SELECT '(i) Current investments', '6', 0, 15, '(b) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN current_investment_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_current_values AS (
    SELECT * FROM other_current_values_raw
    UNION ALL
    SELECT '(c) Other current assets', '11', 0, 20, 'Current assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_current_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
equity_share_values AS (
    SELECT * FROM equity_share_values_raw
    UNION ALL
    SELECT 'Equity Share Capital', '12', 0, 'Equity', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN equity_share_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
current_lease_values AS (
    SELECT * FROM current_lease_values_raw
    UNION ALL
    SELECT '(ii) Lease liabilities', '19', 0, 33, 'Current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN current_lease_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
short_term_values AS (
    SELECT * FROM short_term_values_raw
    UNION ALL
    SELECT '(c) Short-term provisions', '22', 0, 38, 'Current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN short_term_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
income_tax_values AS (
    SELECT * FROM income_tax_values_raw
    UNION ALL
    SELECT '(c) Income tax liabilities (net)', '23', 0, 39, 'Current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN income_tax_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
long_term_values AS (
    SELECT * FROM long_term_values_raw
    UNION ALL
    SELECT '(b) Long-term provisions', '16', 0, 28, 'Non-current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN long_term_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
deferred_tax_values AS (
    SELECT * FROM deferred_tax_values_raw
    UNION ALL
    SELECT '(c) Deferred tax liabilities (Net)', '17', 0, 29, 'Non-current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN deferred_tax_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_equity_values AS (
    SELECT * FROM other_equity_values_raw
    UNION ALL
    SELECT 'Other Equity', '13', 0, 23, 'Equity', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_equity_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
non_current_lease_values AS (
    SELECT * FROM non_current_lease_values_raw
    UNION ALL
    SELECT '(ii) Lease liabilities', '15', 0, 27, 'Non-current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN non_current_lease_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
loans_values AS (
    SELECT * FROM loans_values_raw
    UNION ALL
    SELECT '(v) Loans and advances', '10', 0, 19, '(b) Financial Assets', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN loans_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
long_term_borrowing_values AS (
    SELECT * FROM long_term_borrowing_values_raw
    UNION ALL
    SELECT '(i) Long-term borrowings', '14', 0, 26, '(a) Financial Liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN long_term_borrowing_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
short_term_borrowing_values AS (
    SELECT * FROM short_term_borrowing_values_raw
    UNION ALL
    SELECT '(i) Short Term Borrowings', '18', 0, 32, '(a) Financial Liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN short_term_borrowing_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_trade_values AS (
    SELECT * FROM other_trade_values_raw
    UNION ALL
    SELECT 'a) Total outstanding dues of micro enterprises and small enterprises', '', 0, 35,
           '(iii) Trade and other payables', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_trade_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
micro_trade_values AS (
    SELECT * FROM micro_trade_values_raw
    UNION ALL
    SELECT 'b) Total outstanding dues of other than micro enterprises and small enterprises', '', 0, 36,
           '(iii) Trade and other payables', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN micro_trade_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),
other_current_liabilites_values AS (
    SELECT * FROM other_current_liabilites_values_raw
    UNION ALL
    SELECT '(b) Other current liabilities', '21', 0, 37, 'Current liabilities', tp.agedAsOf::Date
    FROM tillPostingDate tp LEFT JOIN other_current_liabilites_values_raw r ON r.asat = tp.agedAsOf::Date WHERE r.asat IS NULL
),

/* ── Filler / header rows ───────────────────────────────────────────── */
header AS (SELECT 'ASSETS' AS non_current_assets, '' AS noteno, 0 AS amount, 1 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
sub_header1 AS (SELECT 'Non Current Assets' AS non_current_assets, '' AS noteno, 0 AS amount, 2 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
intangible_filler AS (SELECT '(e) Intangible Assets' AS non_current_assets, '' AS noteno, 0 AS amount, 6 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
intangible_filler2 AS (SELECT '(iii) Intangible assets under development' AS non_current_assets, '2(d)' AS noteno, 0 AS amount, 8 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
financial_assets_filler AS (SELECT '(f) Financial Assets' AS non_current_assets, '' AS noteno, 0 AS amount, 9 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
current_assets_filler AS (SELECT 'Current assets' AS non_current_assets, '' AS noteno, 0 AS amount, 12 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
financial_assets_filler2 AS (SELECT '(b) Financial Assets' AS non_current_assets, '' AS noteno, 0 AS amount, 14 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
equity_filler AS (SELECT 'EQUITY and LIABILITIES' AS non_current_assets, '' AS noteno, 0 AS amount, 21 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
non_current_liabilites_filler AS (SELECT 'Non-current liabilities' AS non_current_assets, '' AS noteno, 0 AS amount, 24 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
financial_liabilities_filler AS (SELECT '(a) Financial Liabilities' AS non_current_assets, '' AS noteno, 0 AS amount, 25 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
financial_liabilities_filler2 AS (SELECT '(a) Financial Liabilities' AS non_current_assets, '' AS noteno, 0 AS amount, 31 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
current_liabilites_filler AS (SELECT 'Current liabilities' AS non_current_assets, '' AS noteno, 0 AS amount, 30 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),
trade_filler AS (SELECT '(iii) Trade and other payables' AS non_current_assets, '20' AS noteno, 0 AS amount, 34 AS srno, '' AS subheader, tp.agedAsOf::Date AS asat FROM tillPostingDate tp),

/* ── Totals ─────────────────────────────────────────────────────────── */
totals_base AS (
    SELECT amount, srno, asat FROM ppe_value
    UNION ALL SELECT amount, srno, asat FROM cwp_value
    UNION ALL SELECT amount, srno, asat FROM rtu_value
    UNION ALL SELECT amount, srno, asat FROM intangbile_value
    UNION ALL SELECT amount, srno, asat FROM non_current_values
    UNION ALL SELECT amount, srno, asat FROM other_values
    UNION ALL SELECT amount, srno, asat FROM inventory_values
    UNION ALL SELECT amount, srno, asat FROM current_investment_values
    UNION ALL SELECT amount, 16 AS srno, asat FROM trade_values
    UNION ALL SELECT amount, srno, asat FROM cash_values
    UNION ALL SELECT amount, srno, asat FROM other_cash_values
    UNION ALL SELECT amount, srno, asat FROM loans_values
    UNION ALL SELECT amount, srno, asat FROM other_current_values
    UNION ALL SELECT amount, 22 AS srno, asat FROM equity_share_values
    UNION ALL SELECT amount, srno, asat FROM other_equity_values
    UNION ALL SELECT amount, srno, asat FROM long_term_borrowing_values
    UNION ALL SELECT amount, srno, asat FROM non_current_lease_values
    UNION ALL SELECT amount, srno, asat FROM long_term_values
    UNION ALL SELECT amount, srno, asat FROM deferred_tax_values
    UNION ALL SELECT amount, srno, asat FROM short_term_borrowing_values
    UNION ALL SELECT amount, srno, asat FROM current_lease_values
    UNION ALL SELECT amount, srno, asat FROM other_trade_values
    UNION ALL SELECT amount, srno, asat FROM micro_trade_values
    UNION ALL SELECT amount, srno, asat FROM other_current_liabilites_values
    UNION ALL SELECT amount, srno, asat FROM short_term_values
    UNION ALL SELECT amount, srno, asat FROM income_tax_values
),
totals AS (
    SELECT asat,
           sum(CASE WHEN srno BETWEEN 3 AND 11  THEN amount ELSE 0 END) AS total_nca,
           sum(CASE WHEN srno BETWEEN 13 AND 20 THEN amount ELSE 0 END) AS total_ca,
           sum(CASE WHEN srno IN (22, 23)       THEN amount ELSE 0 END) AS total_equity,
           sum(CASE WHEN srno BETWEEN 26 AND 29 THEN amount ELSE 0 END) AS total_ncl,
           sum(CASE WHEN srno BETWEEN 32 AND 39 THEN amount ELSE 0 END) AS total_cl
    FROM totals_base
    GROUP BY asat
),
totals_derived AS (
    SELECT asat, total_nca, total_ca, total_equity, total_ncl, total_cl,
           total_nca + total_ca                                   AS total_assets,
           total_ncl + total_cl                                   AS total_liabilities,
           total_equity + total_ncl + total_cl                    AS total_equity_and_liabilities,
           (total_nca + total_ca) - (total_equity + total_ncl + total_cl) AS difference
    FROM totals
)

SELECT raw_table.non_current_assets, raw_table.noteno, raw_table.amount AS amount, raw_table.asat, raw_table.srno
FROM (
    SELECT *, 0 AS allow_drilldown FROM header
    UNION ALL SELECT *, 0 AS allow_drilldown FROM sub_header1
    UNION ALL SELECT *, 0 AS allow_drilldown FROM ppe_value
    UNION ALL SELECT *, 0 AS allow_drilldown FROM cwp_value
    UNION ALL SELECT *, 0 AS allow_drilldown FROM rtu_value
    UNION ALL SELECT *, 0 AS allow_drilldown FROM intangible_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM intangbile_value
    UNION ALL SELECT *, 0 AS allow_drilldown FROM intangible_filler2
    UNION ALL SELECT *, 0 AS allow_drilldown FROM financial_assets_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM non_current_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM other_values
    UNION ALL SELECT 'Total Non-current Assets', '', total_nca, 11.5, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT *, 0 AS allow_drilldown FROM current_assets_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM inventory_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM financial_assets_filler2
    UNION ALL SELECT *, 0 AS allow_drilldown FROM current_investment_values
    UNION ALL SELECT non_current_assets, noteno, amount, 16 AS srno, subheader, asat, 0 AS allow_drilldown FROM trade_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM cash_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM other_cash_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM loans_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM other_current_values
    UNION ALL SELECT 'Total Current Assets', '', total_ca, 20.5, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT 'Total Assets', '', total_assets, 20.6, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT *, 0 AS allow_drilldown FROM equity_filler
    UNION ALL SELECT non_current_assets, noteno, amount, 22 AS srno, subheader, asat, 0 AS allow_drilldown FROM equity_share_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM other_equity_values
    UNION ALL SELECT 'Total Equity', '', total_equity, 23.5, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT *, 0 AS allow_drilldown FROM non_current_liabilites_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM long_term_borrowing_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM non_current_lease_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM long_term_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM deferred_tax_values
    UNION ALL SELECT 'Total Non-current liabilities', '', total_ncl, 29.5, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT *, 0 AS allow_drilldown FROM financial_liabilities_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM financial_liabilities_filler2
    UNION ALL SELECT *, 0 AS allow_drilldown FROM current_liabilites_filler
    UNION ALL SELECT *, 0 AS allow_drilldown FROM short_term_borrowing_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM current_lease_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM trade_filler
    UNION ALL SELECT *, 1 AS allow_drilldown FROM other_trade_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM micro_trade_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM other_current_liabilites_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM short_term_values
    UNION ALL SELECT *, 0 AS allow_drilldown FROM income_tax_values
    UNION ALL SELECT 'Total Current liabilities', '', total_cl, 39.5, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT 'Total liabilities', '', total_liabilities, 39.6, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT 'Total Equity and Liabilities', '', total_equity_and_liabilities, 39.7, '', asat, 0 AS allow_drilldown FROM totals_derived
    UNION ALL SELECT 'Difference', '', difference, 39.8, '', asat, 0 AS allow_drilldown FROM totals_derived
) raw_table
ORDER BY raw_table.asat DESC, raw_table.srno ASC