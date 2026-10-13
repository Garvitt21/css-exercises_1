WITH tillPostingDate AS (
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' as DATE) as agedAsOf
    UNION ALL
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' AS DATE) - INTERVAL 3 MONTHS
    UNION ALL
    SELECT CAST(':WHAT_IF_DATE:[Balance sheet ].[tillpostingdate]' AS DATE) - INTERVAL 6 MONTHS
),

/* ── Account mapping: ONE scan of balance_sheet_raw, reused by every *_accounts ── */
bs AS MATERIALIZED (
    select "No.", "sub note", "Sub sub note", "Face "
    FROM [{223}/balance_sheet_raw.xlsx]
),
/* ── GL ledger: ONE scan of glentry+glaccountaq, reused by every *_value_raw ── */
gl_base AS MATERIALIZED (
    select gle.amount as amount,
           tillPostingDate.agedAsOf::Date as asat,
           gla.Name as Name,
           gla.No as No,
           gle.globaldimension1code as globaldimension1code
    FROM [{224}/glentry] gle
    LEFT JOIN [glaccountaq] gla ON gla.NO = gle.glAccountNo
    cross join tillPostingDate
    where gle.postingDate::Date <= tillPostingDate.agedAsOf and Income_Balance = 'Balance Sheet'
),
gl_groups as (
select 'SERVICES' as posting_group , 'Sundry Creditor - Services' as group_name  , '112600' as accno 
union all   
select 'MODULE RM' as posting_group , 'Sundry Creditor - Module RM'  as group_name ,'112000' as accno 
union all 
select 'EPC RM' as posting_group , 'Sundry Creditor - EPC RM' as group_name , '112200' as accno 
union all
select 'CONSUMABLE' as posting_group , 'Sundary Creditor - Consumable' as group_name , '113400'  as accno 
union all
select 'LC FOREIGN' as posting_group , 'Sundry Creditor - LC Foreign' as group_name , '113000' as accno  
union all
select 'IMPORT CONSUMABLE' as posting_group , 'Sundary Creditor - Import Consumable' as group_name , '113600' as accno 
union all 
select 'SERVICES IMPORT' as posting_group , 'Sundary Creditor - Services Import' as group_name , '113900' as accno  
union all
select 'LC INLAND' as posting_group , 'Sundry Creditor - LC Inland' as group_name , '112800' as accno 
union all 
select 'CONTRACT CREDITOR' as posting_group , 'Sundary Creditor -Contract Creditor' as group_name, '113950' as accno 
union all 
select 'IMPORT RM' as posting_group , 'Sundry Creditor - Import RM' as group_name , '111600'  as accno 
union all   
select 'DOMESTICS MACHINARY' as posting_group , 'Sundry Creditor - Domestics Machinary' as group_name ,
'112400' as accno 
union all 
select 'IMPORT MACHINARY' as posting_group , 'Sundry Creditor - Import Machinery' as group_name  , '111800' as accno 
union all 
select 'EXPENSES' as posting_group , 'Sundry Creditor - Expenses' as group_name  ,'113200' as accno 
union all 
select 'EPC COMMERCIAL' as posting_group , 'Sundry Debtors  EPC (Commercial)' as group_name  ,'217800' as accno
union all 
select 'EPC GOVT PROJECT' as posting_group , 'Sundry Debtors EPC (Govt Project)' as group_name  ,'217400' as accno 
union all 
select 'EPC GROUND MOUNTED' as posting_group , 'Sundry Debtors (Ground Mounded)' as group_name  ,'217900' as accno 
union all
select 'EPC ROOF TOP' as posting_group , 'Sundry Debtors  EPC (Roof Top)' as group_name  ,'217600' as accno
union all 
select 'EPC SCRAP' as posting_group , 'Sundry Debtors  EPC (Scrap)' as group_name  ,'218400' as accno
union all 
select 'MODULE DOMESTIC' as posting_group , 'Sundry Debtors Module (Domestic)' as group_name  ,'216800' as accno 
union all
select 'SUSPENSE' as posting_group , 'Suspense Account Debtors' as group_name  ,'124125' as accno
union all
select 'LC DOMESTIC' as posting_group , 'Sundry Debtors LC (Domestic)' as group_name  ,'216700' as accno
union all
select 'MODULE FOREIGN' as posting_group , 'Sundry Debtors Module (Foreign)' as group_name  ,'217000' as accno
union all
select 'MODULE JOB' as posting_group , 'Sundry Debtors Module (JOB)' as group_name  ,'217200' as accno
)

,ppe_accounts as (
    select "No." as accno from bs where "Sub sub note" = 'PPE'
),
cwp_accounts as (
    select "No." as accno from bs where "Sub sub note" like 'Capital%'
),
rtu_accounts as (
    select "No." as accno from bs where "Sub sub note" like 'Right%'
),
intangbile_accounts as (
    select "No." as accno from bs where "Sub sub note" like 'Intangible%'
),
non_current_accounts as (
    select distinct "No." as accno from bs
    where "sub note" in ('Investment in Govt. bonds', 'Investment in Subsidiary', 'Investment in MF')
),
opening_accounts as (
    select distinct "No." as accno from bs
    where "sub note" in ('Allowance for expected credit loss')
),
non_current_lease_accounts as (
    select distinct "No." as accno from bs where "sub note" in ('Lease Liability - INDAS')
),
other_accounts as (
    select distinct "No." as accno from bs where "sub note" in ('Securities Deposits')
),
inventory_accounts as (
    select distinct "No." as accno from bs where "sub note" in ('Finished goods', 'Raw materials')
),
long_term_borrowing_accounts as (
    select distinct "No." as accno from bs
    where "sub note" in ('Secured Term loans from Bank - Long term', 'Loans from Financial institution', 'Loans from directors and related Parties')
),
loans_accounts as (
    select distinct "No." as accno , 'Advance to Staff' as bifercation  from bs
    where "sub note" in ('Advance to Staff')
    union all
    select distinct "No." as accno , 'Advance to Subsidiary' as bifercation  from bs
    where "sub note" in (' Advance to Subsidiary')
    
),
trade_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Unsecured & Considered Good', 'Allowance for expected credit loss')
),
cash_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Balances with Banks in current accounts', 'Balances with Banks in Cash Credit accounts', 'Cash on hand')
),
other_cash_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Fixed Deposits (held as Margin Money against BG/LC and Short TL)')
),
other_current_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Other Receivable', 'Preliminery-Preoperative Expense', 'Prepaid Expenses', 'Balance with Statutory/ Govt. Authorities', 'Subsidy Receivable')
),
equity_share_accounts as (
    select distinct "No." as accno from bs where trim("Face ") in ('Equity Share Capital')
),
other_equity_accounts as (
    select distinct "No." as accno from bs where trim("Face ") in ('Other Equity')
),
short_term_accounts as (
    select distinct "No." as accno , 'Current Gratuity Provision' as bifercation from bs
    where trim("sub note") in ('Current Gratuity Provision')
    union all   
    select distinct "No." as accno , 'Dividend payable' as bifercation from bs
     where trim("sub note") in ('Dividend payable')
),
income_tax_accounts as (
    select distinct "No." as accno from bs where trim("sub note") in ('Provisions for Income Tax')
),
long_term_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Provision for O & M', 'Gratuity Provision', 'Provision For CSR')
),
deferred_tax_accounts as (
    select distinct "No." as accno from bs where trim("sub note") in ('Deferred Tax Liabilities (Net)')
),
short_term_borrowing_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Secured cash credit', 'Current maturities of Long term borrowing', 'Short term unsecured borrowing')
),
other_trade_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Total outstanding dues of Micro Enterprise and small enterprise (MSME)')
),
other_current_liabilites_accounts as (
    select distinct "No." as accno , 'Statutory liabilities' as bifercation from bs
    where trim("sub note") in ('Statutory liabilities')
),

-- ── _raw CTEs ────────────────────────────────────────────────────────────────

ppe_value_raw as (
    select '(a) Property, Plant and Equipment' as non_current_assets, '2(a)' as noteno,
           round(sum(amount), 5) as amount, 3.0::DOUBLE as srno, 'Non Current Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from ppe_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
cwp_value_raw as (
    select '(b) Capital work-in-progress' as non_current_assets, '2(b)' as noteno,
           round(sum(amount), 5) as amount, 4.0::DOUBLE as srno, 'Non Current Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from cwp_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
rtu_value_raw as (
    select '(c) Right-of-use assets' as non_current_assets, '2(c)' as noteno,
           round(sum(amount), 5) as amount, 5.0::DOUBLE as srno, 'Non Current Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from rtu_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
intangbile_value_raw as (
    select '(ii) Other intangible assets' as non_current_assets, '2(a)' as noteno,
           round(sum(amount), 5) as amount, 7.0::DOUBLE as srno, '(e) Intangible Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from intangbile_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
non_current_values_raw as (
    select '(i) Non-current investments' as non_current_assets, '3' as noteno,
           round(sum(amount), 5) as amount, 10.0::DOUBLE as srno, '(f) Financial Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from non_current_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
other_values_raw as (
    select '(ii) Others' as non_current_assets, '4' as noteno,
           round(sum(amount), 5) as amount, 11.0::DOUBLE as srno, '(f) Financial Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from other_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
inventory_values_raw as (
    select '(a) Inventories' as non_current_assets, '5' as noteno,
           round(sum(amount), 5) as amount, 13.0::DOUBLE as srno, 'Current assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from inventory_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
trade_values_raw as (
    select '(ii) Trade and other receivables' as non_current_assets, '7' as noteno,
           round(sum(amount), 5) as amount, '(b) Financial Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from trade_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
cash_values_raw as (
    select '(iii) Cash and cash equivalents' as non_current_assets, '8' as noteno,
           round(sum(amount), 5) as amount, 17.0::DOUBLE as srno, '(b) Financial Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from cash_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
other_cash_values_raw as (
    select '(iv) Bank balances other than Cash and cash equivalents' as non_current_assets, '9' as noteno,
           round(sum(amount), 5) as amount, 18.0::DOUBLE as srno, '(b) Financial Assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from other_cash_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
other_current_values_raw as (
    select '(c) Other current assets' as non_current_assets, '11' as noteno,
           round(sum(amount), 5) as amount, 20.0::DOUBLE as srno, 'Current assets' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from other_current_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
equity_share_values_raw as (
    select 'Equity Share Capital' as non_current_assets, '12' as noteno,
           round(-sum(amount), 5) as amount, 'Equity' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from equity_share_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
current_lease_values_raw as (
    -- No gle alias — APPLY_FILTER not applicable here
    select '(ii) Lease liabilities' as non_current_assets, '19' as noteno,
           round(sum(Repayment), 5) as amount, 33.0::DOUBLE as srno, 'Current liabilities' as subheader,
           tillPostingDate.agedAsOf::Date as asat
    from [lease_liability.xlsx]
    cross join tillPostingDate
    where CAST(strftime('%Y', tillPostingDate.agedAsOf::Date) AS INTEGER) + 1 = CAST(strftime('%Y', Quarter::Date) AS INTEGER)
    group by non_current_assets, noteno, asat
),
short_term_values_raw_base as (
    select  round(-sum(x.amount), 5) as amount,x.asat as asat,la.bifercation as extra ,
            x.Name  as group_name  , x.No as accno,38.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x 
      INNER JOIN  short_term_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar) 
    group by  x.asat , x.Name , x.No , la.bifercation
),
income_tax_values_raw as (
    select '(c) Income tax liabilities (net)' as non_current_assets, '23' as noteno,
           round(-sum(amount), 5) as amount, 39.0::DOUBLE as srno, 'Current liabilities' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from income_tax_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
long_term_values_raw as (
    select '(b) Long-term provisions' as non_current_assets, '16' as noteno,
           round(-sum(amount), 5) as amount, 28.0::DOUBLE as srno, 'Non-current liabilities' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from long_term_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
deferred_tax_values_raw as (
    select '(c) Deferred tax liabilities (Net)' as non_current_assets, '17' as noteno,
           round(-sum(amount), 5) as amount, 29.0::DOUBLE as srno, 'Non-current liabilities' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from deferred_tax_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
other_equity_values_raw as (
    select 'Other Equity' as non_current_assets, '13' as noteno,
           round(-sum(amount), 5) as amount, 23.0::DOUBLE as srno, 'Equity' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from other_equity_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
non_current_lease_values_raw as (
    select ncl.non_current_assets, ncl.noteno,
           round(ncl.amount - cl.amount, 5) as amount,
           ncl.srno, 'Non-current liabilities' as subheader, ncl.asat
    from (
        select '(ii) Lease liabilities' as non_current_assets, '15' as noteno,
               round(-sum(amount), 5) as amount, 27.0::DOUBLE as srno,
               asat
        FROM gl_base
    where 1=1
          and cast(No as varchar) in (select distinct cast(accno as varchar) from non_current_lease_accounts)
          and :APPLY_FILTER:globaldimension1code:
        group by non_current_assets, noteno, asat
    ) as ncl
    join current_lease_values_raw as cl on ncl.asat = cl.asat
),
vendorMachineryPostingGroupsToConsider AS (
  SELECT Code
  FROM [{175}/vle_posting_groups.xlsx]
  WHERE Remark = 'Consider' AND :APPLY_FILTER:Code:
),
vleDetails AS MATERIALIZED (
  SELECT SUM(amountLCY) as amountLCY, SUM(amount) as amount, vendorLedgerEntryNo, currencyCode, tillpostingdate.agedAsOf::Date as asat
  FROM [{175}/detailed_vendor_ledger]
  CROSS JOIN tillpostingdate
  WHERE entryType <> 'Initial Entry' AND CAST(postingDate as date) <= tillPostingDate.agedAsOf::Date
  GROUP BY vendorLedgerEntryNo, currencyCode, asat
),
allDetails AS MATERIALIZED (
  SELECT CAST(v.postingDate as date) as postingDate, v.vendorNo as customerNum, vm.name as customerName, v.entryNo as entryNum, -(vd.amountLCY::numeric) as cdAmount, -(vd.amount::numeric) as cdAmountOrgCur, -(orgAmt.orgAmount::numeric) as orgAmount, -(orgAmt.orgAmountOrgCur::numeric) as orgAmountOrgCur, v.documentNo as docNo, CAST(v.dueDate as date) as dueDate,
  tillPostingDate.agedAsOf::DATE - dueDate::DATE as DueSince, CAST(v.documentDate as date) as docDate, v.documentType as documentType, v.externalDocumentNo as externalDocNo,
  CASE WHEN docNo LIKE 'PUR%' OR docNo LIKE 'PIM%' OR docNo LIKE 'PIM%' THEN 'Invoice' WHEN docNo LIKE 'BP%' OR docNo LIKE 'CP%' THEN 'Payment' WHEN docNo LIKE 'BR%' THEN 'Refund' WHEN docNo LIKE 'PR%' THEN 'Credit Memo' ELSE 'Other Entries' END as _documentType, sctn.State as state,
  COALESCE(Stage3, 'OTHERS') as responsiblePerson,
  CASE WHEN v.invoiceReceivedDate <> '0001-01-01' THEN TRY_CAST(v.invoiceReceivedDate as date) ELSE NULL END as invRecDate, vm.vendorPostingGroup as vendorPostiongGroup, vm.genBusPostingGroup as genBusinessPostingGroup, COALESCE(NULLIF(vd.currencyCode, ''), NULLIF(v.currencyCode, ''), 'INR') as currencyCode, COALESCE(NULLIF(vd.currencyCode, ''), NULLIF(v.currencyCode, ''), 'INR') as _currencyCode, v.Global_Dimension_1_Code as Bcode,
  tillpostingdate.agedAsOf::Date as asat
  FROM [{175}/vle] v
  LEFT JOIN [{175}/vendor_master_] vm ON vm.no = v.vendorNo
  LEFT JOIN [{175}/state_code_to_name.xlsx] sctn ON sctn.stateCode = v.buyerStateCode
  LEFT JOIN (
    SELECT vendorLedgerEntryNo as vlen, amountLCY AS orgAmount, amount AS orgAmountOrgCur
    FROM [detailed_vendor_ledger]
    WHERE entryType = 'Initial Entry'
  ) orgAmt ON orgAmt.vlen = v.entryNo
  CROSS JOIN tillpostingdate
  LEFT JOIN vleDetails vd ON v.entryNo = vd.vendorLedgerEntryNo and vd.asat = tillpostingdate.agedAsOf::Date
  WHERE v.Reversed = False AND postingDate::DATE <= tillPostingDate.agedAsOf::Date AND vm.vendorPostingGroup IN ( SELECT * FROM vendorMachineryPostingGroupsToConsider ) AND :APPLY_FILTER:_documentType: AND :APPLY_FILTER:vm.name: AND :APPLY_FILTER:postingGroup: AND :APPLY_FILTER:vendorPostiongGroup: AND :APPLY_FILTER:genBusinessPostingGroup: AND :APPLY_FILTER:state: AND :APPLY_FILTER:dueDate: and :APPLY_FILTER:_currencyCode: AND :APPLY_FILTER:responsiblePerson: AND v.vendorNo NOT IN ('V00005', 'V00006', 'V01289', 'V01789', 'V01905', 'V01733') AND :APPLY_FILTER:CAST(v.postingDate as date):
),
entryWiseDetails AS MATERIALIZED (
  SELECT postingDate, customerNum, customerName, entryNum, orgAmount, orgAmountOrgCur, IFNULL(SUM(cdAmount), 0) as settleAmount, IFNULL(SUM(cdAmountOrgCur), 0) as settleAmountOrgCur, orgAmountOrgCur + settleAmountOrgCur as AROrgCur, orgAmount + settleAmount as AR, docNo, dueDate, DueSince, docDate, documentType, _documentType, responsiblePerson, state, externalDocNo, invRecDate, vendorPostiongGroup, genBusinessPostingGroup, GROUP_CONCAT(currencyCode) as currencyCode, Bcode,
  asat
  FROM allDetails
  GROUP BY postingDate, customerNum, customerName, entryNum, orgAmount, orgAmountOrgCur, docNo, dueDate, DueSince, docDate, documentType, _documentType, responsiblePerson, state, externalDocNo, invRecDate, vendorPostiongGroup, genBusinessPostingGroup, Bcode, asat
),
unSettledEntries AS MATERIALIZED (
  SELECT postingDate, customerNum, customerName, entryNum, orgAmount, orgAmountOrgCur, orgAmountOrgCur + settleAmountOrgCur as AROrgCur, orgAmount + settleAmount as AR, docNo, dueDate, DueSince, docDate, documentType, _documentType, responsiblePerson, state, externalDocNo, invRecDate, vendorPostiongGroup, genBusinessPostingGroup, currencyCode, 'Solex' as company,
  IFNULL(
      (SELECT Status
       FROM [bank_payment_voucher_rc]
       WHERE accountNo = customerNum
         AND Invoice_External_Doc_No_ = externalDocNo
         AND Status IN ('Pending Approval', 'Open', 'Approved')
         AND appliesToID <> ''
       LIMIT 1),
      'Pending for Process'
    ) AS considered_status,
    asat
  FROM entryWiseDetails
  WHERE orgAmount + settleAmount <> 0 AND :APPLY_FILTER:company:
),
vendorWiseDetails AS MATERIALIZED (
  SELECT customerNum, customerName, SUM(AR) as AR, SUM(AROrgCur) as AROrgCur, responsiblePerson, vendorPostiongGroup, asat
  FROM unSettledEntries
  GROUP BY customerNum, customerName, responsiblePerson, vendorPostiongGroup, asat
),
services_loans__base as (
    SELECT '112600' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'SERVICES'
     group by asat , customernum , customerName
),
services_loans as (
    select * from services_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from services_loans__base) s
    cross join tillPostingDate tp
    left join services_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
import_rm_loans__base as (
    SELECT '111600' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'IMPORT RM'
     group by asat , customernum , customerName
),
import_rm_loans as (
    select * from import_rm_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_rm_loans__base) s
    cross join tillPostingDate tp
    left join import_rm_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_rm_loans__base as (
    SELECT '112000' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'MODULE RM'
     group by asat , customernum , customerName
),
module_rm_loans as (
    select * from module_rm_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_rm_loans__base) s
    cross join tillPostingDate tp
    left join module_rm_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_rm_loans__base as (
    SELECT '112200' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'EPC RM'
     group by asat , customernum , customerName
),
epc_rm_loans as (
    select * from epc_rm_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_rm_loans__base) s
    cross join tillPostingDate tp
    left join epc_rm_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
consumable_loans__base as (
    SELECT '113400' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'CONSUMABLE'
     group by asat , customernum , customerName
),
consumable_loans as (
    select * from consumable_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from consumable_loans__base) s
    cross join tillPostingDate tp
    left join consumable_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
import_consumable_loans__base as (
    SELECT '113600' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'IMPORT CONSUMABLE'
     group by asat , customernum , customerName
),
import_consumable_loans as (
    select * from import_consumable_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_consumable_loans__base) s
    cross join tillPostingDate tp
    left join import_consumable_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
services_import_loans__base as (
    SELECT '113900' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'SERVICES IMPORT'
     group by asat , customernum , customerName
),
services_import_loans as (
    select * from services_import_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from services_import_loans__base) s
    cross join tillPostingDate tp
    left join services_import_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
domestics_loans__base as (
    SELECT '112400' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'DOMESTICS MACHINARY'
     group by asat , customernum , customerName
),
domestics_loans as (
    select * from domestics_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from domestics_loans__base) s
    cross join tillPostingDate tp
    left join domestics_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
import_machinery_loans__base as (
    SELECT '111800' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal < 0 and vendorPostiongGroup = 'IMPORT MACHINERY'
     group by asat , customernum , customerName
),
import_machinery_loans as (
    select * from import_machinery_loans__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_machinery_loans__base) s
    cross join tillPostingDate tp
    left join import_machinery_loans__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
machineryVendorAdvanceResult AS (
 select *  from services_loans
 union all
 select * from import_rm_loans
 union all
 select * from module_rm_loans
 union all
 select * from epc_rm_loans
 union all
 select *  from consumable_loans
 union all
 select * from import_consumable_loans
 union all
 select *  from services_import_loans
 union all
 select * from domestics_loans
 union all
 select * from import_machinery_loans
),
machineryVendorPayableResult as (
 SELECT -sum(AR) as amount, asat ,vendorPostiongGroup FROM (
    SELECT x.* EXCLUDE (customerTotal)
    FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0
  )
  GROUP BY asat ,vendorPostiongGroup
),
machineryVendornetResult as (
 SELECT -sum(AR) as amount, asat ,vendorPostiongGroup FROM (
    SELECT x.* EXCLUDE (customerTotal)
    FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
  )
  GROUP BY asat ,vendorPostiongGroup
),
loans_values_raw_base as (
     select  round(sum(x.amount), 5) as amount,x.asat as asat,la.bifercation as extra ,
            x.Name  as group_name  , x.No as accno,19.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x 
      INNER JOIN loans_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar) 
    group by  x.asat , x.Name , x.No , la.bifercation
),
loans_values_raw as (
    select * from machineryVendorAdvanceResult 
),
long_term_borrowing_values_raw as (
    select '(i) Long-term borrowings' as non_current_assets, '14' as noteno,
           round(-sum(amount), 5) as amount, 26.0::DOUBLE as srno, '(a) Financial Liabilities' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from long_term_borrowing_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
short_term_borrowing_values_raw as (
    select '(i) Short Term Borrowings' as non_current_assets, '18' as noteno,
           round(-sum(amount), 5) as amount, 32.0::DOUBLE as srno, '(a) Financial Liabilities' as subheader,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from short_term_borrowing_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by non_current_assets, noteno, asat
),
other_current_liabilites_values_raw_base as (
  select  -round(sum(x.amount), 5) as amount,x.asat as asat,la.bifercation as extra ,
            x.Name  as group_name  , x.No as accno,37.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x 
      INNER JOIN other_current_liabilites_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar) 
    group by  x.asat , x.Name , x.No , la.bifercation
),

-- ── ECL/ADV provisioning chain (brought over from query2 to feed trade_values) ─

opening_values_raw as (
    select -sum(amount) as amount,
           asat
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from opening_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by asat
),
postingGroupsToConsider AS (
    SELECT Code
    FROM [{175}/cle_posting_group_code.xlsx]
    WHERE Remark = 'Consider' AND :APPLY_FILTER:Code:
),
cleDetails AS MATERIALIZED (
    SELECT *, tillPostingDate.agedAsOf::Date as asat
    FROM [{175}/detailed_cust_ledger]
    CROSS JOIN tillPostingDate
    WHERE entryType <> 'Initial Entry' AND CAST(postingDate as date) <= tillPostingDate.agedAsOf::Date
),

-- ── ECL Chain ────────────────────────────────────────────────────────────────

allDetails_ecl AS MATERIALIZED (
    SELECT
        CAST(c.Posting_Date as date) as postingDate,
        c.Customer_No_ as customerNum,
        c.entryNo as entryNum,
        cd.amountLCY::numeric as cdAmount,
        c.originalAmtLCY as orgAmount,
        cd.postingGroup,
        c.documentNo as docNo,
        CAST(c.dueDate as date) as dueDate,
        tillPostingDate.agedAsOf::Date - dueDate::DATE as DueSince,
        CAST(c.documentDate as date) as docDate,
        COALESCE(cm.name, '') as customerName,
        c.Document_Type as documentType,
        CASE WHEN docNo LIKE 'SI%' THEN 'Invoice'
             WHEN docNo LIKE 'BR%' OR docNo LIKE 'CR%' THEN 'Payment'
             WHEN docNo LIKE 'BP%' THEN 'Refund'
             WHEN docNo LIKE 'CN%' THEN 'Credit Note'
             ELSE 'Other Entries' END as _documentType,
        CASE
            WHEN DueSince >= 730 THEN 'Beyond 2 Years'
            WHEN DueSince >= 365 THEN '1 - 2 Years'
            WHEN DueSince >= 270 THEN '271 - 360 Days'
            WHEN DueSince >= 180 THEN '181 - 270 Days'
            WHEN DueSince >= 90  THEN '91 - 180 Days'
            WHEN DueSince < 0    THEN 'Not Due'
            ELSE '0 - 90 Days'
        END as ageGroup,
        COALESCE(cm.customerPostingGroup, 'SOLEX') as customerPostingGroup,
        bm.Address as branchAddress,
        c.globalDimension1Code as branchCode,
        IFNULL(cm.Stage_4, '') as responsiblePerson,
        tillPostingDate.agedAsOf::Date as asat
    FROM [{175}/cle] c
    LEFT JOIN [{175}/customer_master] cm ON cm.no = c.Customer_No_
    CROSS JOIN tillPostingDate
    LEFT JOIN cleDetails cd ON c.entryNo = cd.custLedgerEntryNo AND cd.asat = tillPostingDate.agedAsOf::Date
    LEFT JOIN [{175}/branch_map.xlsx] bm ON c.globalDimension1Code = bm.Branch
    WHERE c.Reversed = False
      AND CAST(c.Posting_Date as date) <= tillPostingDate.agedAsOf::Date
      AND :APPLY_FILTER:cm.name:
      AND c.customerPostingGroup IN (SELECT * FROM postingGroupsToConsider)
      AND :APPLY_FILTER:branchCode:
      AND :APPLY_FILTER:_documentType:
      AND :APPLY_FILTER:ageGroup:
      AND :APPLY_FILTER:COALESCE(cm.customerPostingGroup, 'SOLEX'):
      AND :APPLY_FILTER:bm.Address:
      AND :APPLY_FILTER:responsiblePerson:
      AND :APPLY_FILTER:CAST(c.Posting_Date as date):
),
entryWiseDetails_ecl AS MATERIALIZED (
    SELECT postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
           IFNULL(SUM(cdAmount), 0) as settleAmount,
           orgAmount + settleAmount as AR,
           docNo, dueDate, DueSince, docDate, customerName, documentType,
           branchAddress, branchCode, responsiblePerson, asat
    FROM allDetails_ecl
    GROUP BY postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
             docNo, dueDate, DueSince, docDate, customerName, documentType,
             branchAddress, branchCode, responsiblePerson, asat
),
_unSettledEntries_ecl AS MATERIALIZED (
    SELECT * FROM entryWiseDetails_ecl WHERE orgAmount + settleAmount <> 0
),
customersWithAdvance_ecl AS (
    SELECT _use.customerNum, asat
    FROM _unSettledEntries_ecl _use
    LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                         AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                    THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM _unSettledEntries_ecl GROUP BY customerNum, asat
    ) x ON x.customerNum = _use.customerNum AND x.asat = _use.asat
    WHERE bothSign = 0
    GROUP BY _use.customerNum, bothSign, asat
    HAVING SUM(AR) < 0
),
unSettledEntries_ecl AS MATERIALIZED (
    SELECT postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
           settleAmount, AR, docNo, dueDate, DueSince, docDate, customerName,
           documentType, branchAddress, branchCode, responsiblePerson,
           'Solex' as company, asat
    FROM entryWiseDetails_ecl
    WHERE orgAmount + settleAmount <> 0
),
customerWiseDetails_ecl AS MATERIALIZED (
    SELECT customerNum, customerPostingGroup, SUM(AR) as AR,
           CASE
               WHEN DueSince >= 730 THEN 'Beyond 2 Years'
               WHEN DueSince >= 365 THEN '1 - 2 Years'
               WHEN DueSince >= 270 THEN '271 - 360 Days'
               WHEN DueSince >= 180 THEN '181 - 270 Days'
               WHEN DueSince >= 90  THEN '91 - 180 Days'
               WHEN DueSince < 0    THEN 'Not Due'
               ELSE '0 - 90 Days'
           END as ageGroup,
           customerName, responsiblePerson, asat
    FROM unSettledEntries_ecl
    GROUP BY customerNum, customerPostingGroup, ageGroup, customerName, responsiblePerson, asat
),
provision_result AS (
    SELECT
        asat,
        sum(CASE WHEN ageGroup = '1 - 2 Years'    THEN AR ELSE 0 END) * 0.10 +
        sum(CASE WHEN ageGroup = 'Beyond 2 Years' THEN AR ELSE 0 END) * 0.20 AS provision_amount
    FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_ecl.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_ecl.customerNum, customerWiseDetails_ecl.asat) AS customerTotal,
                   customerWiseDetails_ecl.asat
            FROM customerWiseDetails_ecl
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_ecl
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_ecl.customerNum = x.customerNum
                AND customerWiseDetails_ecl.customerName = x.customerName
                AND customerWiseDetails_ecl.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_ecl
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    )
    WHERE lower(customerPostingGroup) IN (
        'epc commercial', 'epc govt project', 'epc ground mounted', 'epc roof top',
        'module domestic', 'module foreign', 'epc scrap', 'suspense'
    )
    GROUP BY asat
),

-- ── ADV Chain ────────────────────────────────────────────────────────────────

allDetails_adv AS MATERIALIZED (
    SELECT
        CAST(c.Posting_Date as date) as postingDate,
        c.Customer_No_ as customerNum,
        c.entryNo as entryNum,
        cd.amountLCY::numeric as cdAmount,
        c.originalAmtLCY as orgAmount,
        cd.postingGroup,
        c.documentNo as docNo,
        CAST(c.dueDate as date) as dueDate,
        tillPostingDate.agedAsOf::Date - dueDate::DATE as DueSince,
        CAST(c.documentDate as date) as docDate,
        COALESCE(cm.name, '') as customerName,
        c.Document_Type as documentType,
        CASE WHEN docNo LIKE 'SI%' THEN 'Invoice'
             WHEN docNo LIKE 'BR%' OR docNo LIKE 'CR%' THEN 'Payment'
             WHEN docNo LIKE 'BP%' THEN 'Refund'
             WHEN docNo LIKE 'CN%' THEN 'Credit Note'
             ELSE 'Other Entries' END as _documentType,
        CASE WHEN DueSince >= 360 THEN '360 + Days'
             WHEN DueSince >= 270 THEN '271 - 360 Days'
             WHEN DueSince >= 180 THEN '181 - 270 Days'
             WHEN DueSince >= 90  THEN '91 - 180 Days'
             WHEN DueSince < 0    THEN 'Not Due'
             ELSE '0 - 90 Days' END as ageGroup,
        COALESCE(cm.customerPostingGroup, 'SOLEX') as customerPostingGroup,
        bm.Address as branchAddress,
        c.globalDimension1Code as branchCode,
        IFNULL(cm.Stage_4, '') as responsiblePerson,
        tillPostingDate.agedAsOf::Date as asat
    FROM [{175}/cle] c
    LEFT JOIN [{175}/customer_master] cm ON cm.no = c.Customer_No_
    CROSS JOIN tillPostingDate
    LEFT JOIN cleDetails cd ON c.entryNo = cd.custLedgerEntryNo AND cd.asat = tillPostingDate.agedAsOf::Date
    LEFT JOIN [{175}/branch_map.xlsx] bm ON c.globalDimension1Code = bm.Branch
    WHERE c.Reversed = False
      AND CAST(c.Posting_Date as date) <= tillPostingDate.agedAsOf::Date
      AND :APPLY_FILTER:cm.name:
      AND c.customerPostingGroup IN (SELECT * FROM postingGroupsToConsider)
      AND :APPLY_FILTER:branchCode:
      AND :APPLY_FILTER:_documentType:
      AND :APPLY_FILTER:ageGroup:
      AND :APPLY_FILTER:COALESCE(cm.customerPostingGroup, 'SOLEX'):
      AND :APPLY_FILTER:bm.Address:
      AND :APPLY_FILTER:responsiblePerson:
      AND :APPLY_FILTER:CAST(c.Posting_Date as date):
),
entryWiseDetails_adv AS MATERIALIZED (
    SELECT postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
           IFNULL(SUM(cdAmount), 0) as settleAmount,
           orgAmount + settleAmount as AR,
           docNo, dueDate, DueSince, docDate, customerName, documentType,
           branchAddress, branchCode, responsiblePerson, asat
    FROM allDetails_adv
    GROUP BY postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
             docNo, dueDate, DueSince, docDate, customerName, documentType,
             branchAddress, branchCode, responsiblePerson, asat
),
_unSettledEntries_adv AS MATERIALIZED (
    SELECT * FROM entryWiseDetails_adv WHERE orgAmount + settleAmount <> 0
),
customersWithAdvance_adv AS (
    SELECT _use.customerNum, asat
    FROM _unSettledEntries_adv _use
    LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                         AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                    THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM _unSettledEntries_adv GROUP BY customerNum, asat
    ) x ON x.customerNum = _use.customerNum AND x.asat = _use.asat
    WHERE bothSign = 0
    GROUP BY _use.customerNum, bothSign, asat
    HAVING SUM(AR) < 0
),
unSettledEntries_adv AS MATERIALIZED (
    SELECT postingDate, customerNum, customerPostingGroup, entryNum, orgAmount,
           settleAmount, AR, docNo, dueDate, DueSince, docDate, customerName,
           documentType, branchAddress, branchCode, responsiblePerson,
           'Solex' as company, asat
    FROM entryWiseDetails_adv
    WHERE orgAmount + settleAmount <> 0
),
customerWiseDetails_adv AS MATERIALIZED (
    SELECT customerNum, customerPostingGroup, SUM(AR) as AR,
           CASE WHEN DueSince >= 360 THEN '360 + Days'
                WHEN DueSince >= 270 THEN '271 - 360 Days'
                WHEN DueSince >= 180 THEN '181 - 270 Days'
                WHEN DueSince >= 90  THEN '91 - 180 Days'
                WHEN DueSince < 0    THEN 'Not Due'
                ELSE '0 - 90 Days' END as ageGroup,
           customerName, responsiblePerson, asat
    FROM unSettledEntries_adv
    GROUP BY customerNum, customerPostingGroup, ageGroup, customerName, responsiblePerson, asat
)
,
epc_commercial_other_current__base as (
    SELECT '217800' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'epc commercial'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_commercial_other_current as (
    select * from epc_commercial_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_commercial_other_current__base) s
    cross join tillPostingDate tp
    left join epc_commercial_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_govt_project_other_current__base as (
    SELECT '217400' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'epc govt project'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_govt_project_other_current as (
    select * from epc_govt_project_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_govt_project_other_current__base) s
    cross join tillPostingDate tp
    left join epc_govt_project_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_ground_mounted_other_current__base as (
    SELECT '217900' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'epc ground mounted'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_ground_mounted_other_current as (
    select * from epc_ground_mounted_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_ground_mounted_other_current__base) s
    cross join tillPostingDate tp
    left join epc_ground_mounted_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_roof_top_other_current__base as (
    SELECT '217600' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'epc roof top'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_roof_top_other_current as (
    select * from epc_roof_top_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_roof_top_other_current__base) s
    cross join tillPostingDate tp
    left join epc_roof_top_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_scrap_other_current__base as (
    SELECT '218400' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'epc scrap'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_scrap_other_current as (
    select * from epc_scrap_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_scrap_other_current__base) s
    cross join tillPostingDate tp
    left join epc_scrap_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_domestic_other_current__base as (
    SELECT '216800' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'module domestic'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
module_domestic_other_current as (
    select * from module_domestic_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_domestic_other_current__base) s
    cross join tillPostingDate tp
    left join module_domestic_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_foreign_other_current__base as (
    SELECT '217000' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'module foreign'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
module_foreign_other_current as (
    select * from module_foreign_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_foreign_other_current__base) s
    cross join tillPostingDate tp
    left join module_foreign_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
suspense_other_current__base as (
    SELECT '124125' as accno , asat , customerNum , customerName , -round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal < 0 and lower(customerPostingGroup) = 'suspense'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
suspense_other_current as (
    select * from suspense_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from suspense_other_current__base) s
    cross join tillPostingDate tp
    left join suspense_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
lc_domestic_trade_receviables__base as (
    SELECT '216700' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'LC DOMESTIC'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
lc_domestic_trade_receviables as (
    select * from lc_domestic_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from lc_domestic_trade_receviables__base) s
    cross join tillPostingDate tp
    left join lc_domestic_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_domestic_trade_receviables__base as (
    SELECT '216800' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'MODULE DOMESTIC'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
module_domestic_trade_receviables as (
    select * from module_domestic_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_domestic_trade_receviables__base) s
    cross join tillPostingDate tp
    left join module_domestic_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_foreign_trade_receviables__base as (
    SELECT '217000' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'MODULE FOREIGN'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
module_foreign_trade_receviables as (
    select * from module_foreign_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_foreign_trade_receviables__base) s
    cross join tillPostingDate tp
    left join module_foreign_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_job_trade_receviables__base as (
    SELECT '217200' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'MODULE JOB'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
module_job_trade_receviables as (
    select * from module_job_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_job_trade_receviables__base) s
    cross join tillPostingDate tp
    left join module_job_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_govt_project_trade_receviables__base as (
    SELECT '217400' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'EPC GOVT PROJECT'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_govt_project_trade_receviables as (
    select * from epc_govt_project_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_govt_project_trade_receviables__base) s
    cross join tillPostingDate tp
    left join epc_govt_project_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_roof_top_trade_receviables__base as (
    SELECT '217600' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'EPC ROOF TOP'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_roof_top_trade_receviables as (
    select * from epc_roof_top_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_roof_top_trade_receviables__base) s
    cross join tillPostingDate tp
    left join epc_roof_top_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_commercial_trade_receviables__base as (
    SELECT '217800' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'EPC COMMERCIAL'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_commercial_trade_receviables as (
    select * from epc_commercial_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_commercial_trade_receviables__base) s
    cross join tillPostingDate tp
    left join epc_commercial_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_ground_mounted_trade_receviables__base as (
    SELECT '217900' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'EPC GROUND MOUNTED'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_ground_mounted_trade_receviables as (
    select * from epc_ground_mounted_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_ground_mounted_trade_receviables__base) s
    cross join tillPostingDate tp
    left join epc_ground_mounted_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_scrap_trade_receviables__base as (
    SELECT '218400' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'EPC SCRAP'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
epc_scrap_trade_receviables as (
    select * from epc_scrap_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_scrap_trade_receviables__base) s
    cross join tillPostingDate tp
    left join epc_scrap_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
suspense_trade_receviables__base as (
    SELECT '124125' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
        SELECT customerNum, customerPostingGroup, SUM(AR) AS AR, ageGroup,
               customerName, responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
        FROM (
            SELECT customerWiseDetails_adv.*,
                   COALESCE(x.avgDueDaysSince::VARCHAR, '') AS avgDueDaysSince,
                   x.avgDueDaysSinceDue,
                   CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END AS color,
                   SUM(AR) OVER (PARTITION BY customerWiseDetails_adv.customerNum, customerWiseDetails_adv.asat) AS customerTotal,
                   customerWiseDetails_adv.asat
            FROM customerWiseDetails_adv
            LEFT JOIN (
                SELECT customerNum, customerName,
                       AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
                       CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL
                            THEN CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days')
                            ELSE '-' END AS avgDueDaysSinceDue, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) x ON customerWiseDetails_adv.customerNum = x.customerNum
                AND customerWiseDetails_adv.customerName = x.customerName
                AND customerWiseDetails_adv.asat = x.asat
            LEFT JOIN (
                SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0
                                 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0
                            THEN 1 ELSE 0 END AS bothSign,
                       customerNum, customerName, asat
                FROM unSettledEntries_adv
                GROUP BY customerNum, customerName, asat
            ) y ON y.customerNum = x.customerNum
                AND x.customerName = y.customerName
                AND y.asat = x.asat
        ) x
        WHERE customerTotal > 0 and TRIM(customerPostingGroup) = 'SUSPENSE'
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    ) x
    GROUP BY asat , customerNum , customerName
),
suspense_trade_receviables as (
    select * from suspense_trade_receviables__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from suspense_trade_receviables__base) s
    cross join tillPostingDate tp
    left join suspense_trade_receviables__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
q2_final AS (
   select * from lc_domestic_trade_receviables
   union all
   select * from module_domestic_trade_receviables
   union all
   select * from module_foreign_trade_receviables
   union all
   select * from module_job_trade_receviables
   union all
   select * from epc_govt_project_trade_receviables
   union all
   select * from epc_roof_top_trade_receviables
   union all
   select * from epc_commercial_trade_receviables
   union all
   select * from epc_ground_mounted_trade_receviables
   union all
   select * from epc_scrap_trade_receviables
   union all
   select * from suspense_trade_receviables
)
,
expenses_other_current__base as (
    SELECT '113200' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE vendorPostiongGroup = 'EXPENSES'
     group by asat , customernum , customerName
),
expenses_other_current as (
    select * from expenses_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from expenses_other_current__base) s
    cross join tillPostingDate tp
    left join expenses_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
domestics_machinary_other_current__base as (
    SELECT '112400' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and vendorPostiongGroup = 'DOMESTICS MACHINARY'
     group by asat , customernum , customerName
),
domestics_machinary_other_current as (
    select * from domestics_machinary_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from domestics_machinary_other_current__base) s
    cross join tillPostingDate tp
    left join domestics_machinary_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
import_machinery_other_current__base as (
    SELECT '111800' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and vendorPostiongGroup = 'IMPORT MACHINERY'
     group by asat , customernum , customerName
),
import_machinery_other_current as (
    select * from import_machinery_other_current__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_machinery_other_current__base) s
    cross join tillPostingDate tp
    left join import_machinery_other_current__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_current_liabilites_values_raw as (

  select * from epc_commercial_other_current
  union all
  select * from epc_govt_project_other_current
  union all
  select * from epc_ground_mounted_other_current
  union all
  select * from epc_roof_top_other_current
  union all
  select * from epc_scrap_other_current
  union all
  select * from module_domestic_other_current
  union all
  select * from module_foreign_other_current
  union all
  select * from suspense_other_current
  union all
  select * from expenses_other_current
  union all
  select * from domestics_machinary_other_current
  union all
  select * from import_machinery_other_current
)
,
msme_data as (
  select TRIM(no) as vendorno  from [{175}/vendor_master_] 
    where  TRIM(MSME_Type) <> ''   
  
),
non_msme as (
select TRIM(no) as vendorno  from [{175}/vendor_master_] 
  where  TRIM(MSME_Type) = '' 
)
,
other_trade_values_raw as (
    select x.* EXCLUDE(posting_group) , gg.*EXCLUDE(posting_group) , 35.0::DOUBLE as srno  from (
   select round(sum(AR),5) as amount,  asat , vendorPostiongGroup as posting_group   , '' as extra  from (
              SELECT x.* EXCLUDE (customerTotal) FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from msme_data) and vendorPostiongGroup 
    not in ('EXPENSES' , 'DOMESTICS MACHINARY' ,'IMPORT MACHINARY', 'CONTRACT CREDITOR')
    ) group by asat , vendorPostiongGroup
    ) x
    INNER JOIN 
    gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group)) 
)
,
services_micro__base as (
    SELECT '112600' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount  FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'SERVICES'
     group by asat , customernum , customerName
),
services_micro as (
    select * from services_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from services_micro__base) s
    cross join tillPostingDate tp
    left join services_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
import_rm_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'IMPORT RM'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
import_rm_micro as (
    select * from import_rm_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_rm_micro__base) s
    cross join tillPostingDate tp
    left join import_rm_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
module_rm_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'MODULE RM'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
module_rm_micro as (
    select * from module_rm_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_rm_micro__base) s
    cross join tillPostingDate tp
    left join module_rm_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
epc_rm_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'EPC RM'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
epc_rm_micro as (
    select * from epc_rm_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_rm_micro__base) s
    cross join tillPostingDate tp
    left join epc_rm_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
lc_foreign_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'LC FOREIGN'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
lc_foreign_micro as (
    select * from lc_foreign_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from lc_foreign_micro__base) s
    cross join tillPostingDate tp
    left join lc_foreign_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
consumable_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'CONSUMABLE'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
consumable_micro as (
    select * from consumable_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from consumable_micro__base) s
    cross join tillPostingDate tp
    left join consumable_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
import_consumable_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'IMPORT CONSUMABLE'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
import_consumable_micro as (
    select * from import_consumable_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from import_consumable_micro__base) s
    cross join tillPostingDate tp
    left join import_consumable_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
services_import_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'SERVICES IMPORT'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
services_import_micro as (
    select * from services_import_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from services_import_micro__base) s
    cross join tillPostingDate tp
    left join services_import_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
contract_creditor_micro__base as (
    select gg.accno , x.asat , x.customerNum , x.customerName , x.amount from (
      SELECT asat , customerNum , customerName , vendorPostiongGroup as posting_group , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup = 'CONTRACT CREDITOR'
     group by asat , customernum , customerName , vendorPostiongGroup
    ) x
    INNER JOIN gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
contract_creditor_micro as (
    select * from contract_creditor_micro__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from contract_creditor_micro__base) s
    cross join tillPostingDate tp
    left join contract_creditor_micro__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
services_other__base as (
    SELECT  '112600' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from msme_data) and vendorPostiongGroup = 'SERVICES' 
    group by asat , customernum , customerName
),
services_other as (
    select * from services_other__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from services_other__base) s
    cross join tillPostingDate tp
    left join services_other__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
module_rm_other__base as (
    SELECT  '112000' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from msme_data) and vendorPostiongGroup = 'MODULE RM' 
    group by asat , customernum , customerName
),
module_rm_other as (
    select * from module_rm_other__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from module_rm_other__base) s
    cross join tillPostingDate tp
    left join module_rm_other__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
consumable_other__base as (
    SELECT  '113400' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from msme_data) and vendorPostiongGroup = 'CONSUMABLE' 
    group by asat , customernum , customerName
),
consumable_other as (
    select * from consumable_other__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from consumable_other__base) s
    cross join tillPostingDate tp
    left join consumable_other__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
epc_rm_other__base as (
    SELECT  '112200' as accno , asat , customerNum , customerName , round(sum(AR),5) as amount FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from msme_data) and vendorPostiongGroup = 'EPC RM' 
    group by asat , customernum , customerName
),
epc_rm_other as (
    select * from epc_rm_other__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from epc_rm_other__base) s
    cross join tillPostingDate tp
    left join epc_rm_other__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_trade_values as (
 select * from services_other
 union all
 select * from module_rm_other
 union all
 select * from consumable_other
 union all
 select * from epc_rm_other
)
,
other_short_term_provision__base as (
 SELECT '113960' as accno , asat , customerNum , customerName , round(COALESCE(sum(AR),0),5)  as amount
    FROM (
      SELECT vendorWiseDetails.*, COALESCE(x.avgDueDaysSince::VARCHAR, '') as avgDueDaysSince, x.avgDueDaysSinceDue, CASE WHEN y.bothSign THEN '#00828F' ELSE 'black' END as color, SUM(AR) OVER (PARTITION BY vendorWiseDetails.customerNum, vendorWiseDetails.asat) as customerTotal, x.currencyCode, vendorWiseDetails.asat
      FROM vendorWiseDetails
      LEFT JOIN (
       SELECT
            customerNum,
            AVG(CASE WHEN DueSince > 0 THEN DueSince END) AS avgDueDaysSince,
            CASE WHEN AVG(CASE WHEN DueSince <= 0 THEN DueSince END) IS NOT NULL THEN
            CONCAT(-AVG(CASE WHEN DueSince <= 0 THEN DueSince END)::INT, ' days') ELSE '-' END AS avgDueDaysSinceDue,
            STRING_AGG(DISTINCT currencyCode, ', ') as currencyCode,
            asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) x ON vendorWiseDetails.customerNum = x.customerNum and vendorWiseDetails.asat = x.asat
      LEFT JOIN (
        SELECT CASE WHEN COUNT(CASE WHEN AR > 0 THEN 1 END) > 0 AND COUNT(CASE WHEN AR < 0 THEN 1 END) > 0 THEN 1 ELSE 0 END as bothSign, customerNum, asat
        FROM unSettledEntries
        GROUP BY customerNum, asat
      ) y ON y.customerNum = x.customerNum and y.asat = x.asat
      WHERE (AR >= 0.5 OR AR <= -0.5)
    ) x
    WHERE customerTotal > 0 and vendorPostiongGroup = 'PROVISION CREDITOR'
   GROUP BY  accno , asat , customerNum , customerName
),
other_short_term_provision as (
    select * from other_short_term_provision__base
    union all
    select s.accno as accno, tp.agedAsOf::Date as asat, s.customerNum as customerNum, s.customerName as customerName, 0 as amount
    from (select distinct accno, customerNum, customerName from other_short_term_provision__base) s
    cross join tillPostingDate tp
    left join other_short_term_provision__base r on r.accno = s.accno and r.customerNum = s.customerNum and r.customerName = s.customerName and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
short_term_values_raw as (
  select * from other_short_term_provision 
),
micro_trade_values as (
 select * from services_micro
 union all
 select * from import_rm_micro
 union all
 select * from module_rm_micro
 union all
 select * from epc_rm_micro
 union all
 select * from lc_foreign_micro
 union all
 select * from consumable_micro
 union all
 select * from import_consumable_micro
 union all
 select * from services_import_micro
 union all
 select * from contract_creditor_micro
)
-- ── _value CTEs: per-partition fallback ────────────────────────────────────
-- select * from other_trade_values_raw 
-- union all
-- select * from micro_trade_values
-- union all
-- select * from loans_values_raw
-- union all 
-- select * from short_term_values_raw
-- union all 
-- select * from other_current_liabilites_values_raw
-- where srno =  :APPLY_DRILL_FILTER:srno:
select * from (
select 35.0::DOUBLE as srno , * from other_trade_values
union all   
select 36.0::DOUBLE as srno,  * from micro_trade_values
union all 
select 19.0::DOUBLE as srno , * from loans_values_raw 
union all   
select 38.0::DOUBLE as srno , * from short_term_values_raw
union all
select 37.0::DOUBLE as srno , * from other_current_liabilites_values_raw
union all 
select 16.0::DOUBLE as srno , * from q2_final 
)
where accno = :APPLY_DRILL_FILTER:accno: and srno::DECIMAL(11,1)::VARCHAR = :APPLY_DRILL_FILTER:srno:
