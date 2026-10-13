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
    select distinct "No." as accno, '' as bifercation from bs where "Sub sub note" = 'PPE'
),
cwp_accounts as (
    select distinct "No." as accno, '' as bifercation from bs where "Sub sub note" like 'Capital%'
),
rtu_accounts as (
    select distinct "No." as accno, '' as bifercation from bs where "Sub sub note" like 'Right%'
),
intangbile_accounts as (
    select distinct "No." as accno, '' as bifercation from bs where "Sub sub note" like 'Intangible%'
),
non_current_accounts as (
    select distinct "No." as accno, 'Investment in Govt. bonds' as bifercation from bs
    where "sub note" = 'Investment in Govt. bonds'
    union all
    select distinct "No." as accno, 'Investment in Subsidiary' as bifercation from bs
    where "sub note" = 'Investment in Subsidiary'
    union all
    select distinct "No." as accno, 'Investment in MF' as bifercation from bs
    where "sub note" = 'Investment in MF'
),
non_current_lease_accounts as (
    select distinct "No." as accno , 'Lease Liability - INDAS' as bifercation from bs where "sub note" in ('Lease Liability - INDAS') 
),
other_accounts as (
    select distinct "No." as accno, 'Securities Deposits' as bifercation from bs where "sub note" = 'Securities Deposits'
),
inventory_accounts as (
    select distinct "No." as accno, 'Finished goods' as bifercation from bs where "sub note" = 'Finished goods'
    union all
    select distinct "No." as accno, 'Raw materials' as bifercation from bs where "sub note" = 'Raw materials'
),
long_term_borrowing_accounts as (
    select distinct "No." as accno, 'Secured Term loans from Bank - Long term' as bifercation from bs
    where "sub note" = 'Secured Term loans from Bank - Long term'
    union all
    select distinct "No." as accno, 'Loans from directors and related Parties' as bifercation from bs
    where "sub note" = 'Loans from directors and related Parties'
),
loans_accounts as (
    select distinct "No." as accno , 'Advance to Staff' as bifercation  from bs
    where "sub note" in ('Advance to Staff')
    union all
    select distinct "No." as accno , 'Advance to Subsidiary' as bifercation  from bs
    where "sub note" in (' Advance to Subsidiary')
    
),
trade_accounts as (
    select distinct "No." as accno , 'Allowance for expected credit loss' as bifercation  from bs
    where trim("sub note") = 'Allowance for expected credit loss'
),
cash_accounts as (
    select distinct "No." as accno, 'Balances with Banks in current accounts' as bifercation from bs
    where trim("sub note") = 'Balances with Banks in current accounts'
    union all
    select distinct "No." as accno, 'Balances with Banks in Cash Credit accounts' as bifercation from bs
    where trim("sub note") = 'Balances with Banks in Cash Credit accounts'
    union all
    select distinct "No." as accno, 'Cash on hand' as bifercation from bs
    where trim("sub note") = 'Cash on hand'
),
other_cash_accounts as (
    select distinct "No." as accno, 'Fixed Deposits (held as Margin Money against BG/LC and Short TL)' as bifercation from bs
    where trim("sub note") = 'Fixed Deposits (held as Margin Money against BG/LC and Short TL)'
),
current_investment_accounts as (
    select distinct "No." as accno, 'Current Investment' as bifercation from bs
    where trim("sub note") = 'Current Investment'
),
other_current_accounts as (
    select distinct "No." as accno, 'Other Receivable' as bifercation from bs
    where trim("sub note") = 'Other Receivable'
    union all
    select distinct "No." as accno, 'Preliminery-Preoperative Expense' as bifercation from bs
    where trim("sub note") = 'Preliminery-Preoperative Expense'
    union all
    select distinct "No." as accno, 'Prepaid Expenses' as bifercation from bs
    where trim("sub note") = 'Prepaid Expenses'
    union all
    select distinct "No." as accno, 'Balance with Statutory/ Govt. Authorities' as bifercation from bs
    where trim("sub note") = 'Balance with Statutory/ Govt. Authorities'
    union all
    select distinct "No." as accno, 'Subsidy Receivable' as bifercation from bs
    where trim("sub note") = 'Subsidy Receivable'
),
equity_share_accounts as (
    select distinct "No." as accno, '' as bifercation from bs where trim("Face ") = 'Equity Share Capital'
),
other_equity_accounts as (
    select distinct "No." as accno, '' as bifercation from bs where trim("Face ") = 'Other Equity'
),
short_term_accounts as (
    select distinct "No." as accno , 'Current Gratuity Provision' as bifercation from bs
    where trim("sub note") in ('Current Gratuity Provision')
    union all   
    select distinct "No." as accno , 'Dividend payable' as bifercation from bs
     where trim("sub note") in ('Dividend payable')
),
income_tax_accounts as (
    select distinct "No." as accno, 'Provisions for Income Tax' as bifercation from bs where trim("sub note") = 'Provisions for Income Tax'
),
long_term_accounts as (
    select distinct "No." as accno, 'Provision for O & M' as bifercation from bs
    where trim("sub note") = 'Provision for O & M'
    union all
    select distinct "No." as accno, 'Gratuity Provision' as bifercation from bs
    where trim("sub note") = 'Gratuity Provision'
    union all
    select distinct "No." as accno, 'Provision For CSR' as bifercation from bs
    where trim("sub note") = 'Provision For CSR'
),
deferred_tax_accounts as (
    select distinct "No." as accno, 'Deferred Tax Liabilities (Net)' as bifercation from bs where trim("sub note") = 'Deferred Tax Liabilities (Net)'
),
short_term_borrowing_accounts as (
    select distinct "No." as accno, 'Secured cash credit' as bifercation from bs
    where trim("sub note") = 'Secured cash credit'
    union all
    select distinct "No." as accno, 'Short term unsecured borrowing' as bifercation from bs
    where trim("sub note") = 'Loans from Financial institution'
),
other_trade_accounts as (
    select distinct "No." as accno from bs
    where trim("sub note") in ('Total outstanding dues of Micro Enterprise and small enterprise (MSME)')
),
micro_trade_accounts as (
      select '112800'  as accno
    union all 
    select '121000' as accno 
    union all 
    select '124100' as accno 
),
other_current_liabilites_accounts as (
    select distinct "No." as accno , 'Statutory liabilities' as bifercation from bs
    where trim("sub note") in ('Statutory liabilities')
),

-- ── _raw CTEs ────────────────────────────────────────────────────────────────
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
unsecured_loan_master as (
    select
        Date::Date as loan_date,
        Principal as principal,
        "GL CODE" as gl_code,
        min(Date::Date) over (partition by "GL CODE") as loan_first_date
    from [loan_master_unsecured.xlsx]
),
unsecured_loan_next12_values_raw as (
    select round(sum(slm.principal), 5) as amount,
           tp.agedAsOf::Date as asat
    from (
        select agedAsOf,
               (date_trunc('month', agedAsOf::Date) + INTERVAL 1 MONTH)::Date as window_start
        from tillPostingDate
    ) tp
    cross join unsecured_loan_master slm
    where slm.loan_first_date <= tp.window_start
      and slm.loan_date >= tp.window_start
      and slm.loan_date <= tp.window_start + INTERVAL 12 MONTHS
    group by tp.agedAsOf
),
ppe_value_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 3.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN ppe_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
ppe_value_raw as (
    select * from ppe_value_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from ppe_value_raw__base) s
    cross join tillPostingDate tp
    left join ppe_value_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
cwp_value_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 4.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN cwp_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
cwp_value_raw as (
    select * from cwp_value_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from cwp_value_raw__base) s
    cross join tillPostingDate tp
    left join cwp_value_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
rtu_value_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 5.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN rtu_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
rtu_value_raw as (
    select * from rtu_value_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from rtu_value_raw__base) s
    cross join tillPostingDate tp
    left join rtu_value_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
intangbile_value_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 7.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN intangbile_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
intangbile_value_raw as (
    select * from intangbile_value_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from intangbile_value_raw__base) s
    cross join tillPostingDate tp
    left join intangbile_value_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
non_current_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 10.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN non_current_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
non_current_values_raw as (
    select * from non_current_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from non_current_values_raw__base) s
    cross join tillPostingDate tp
    left join non_current_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 11.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN other_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
other_values_raw as (
    select * from other_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_values_raw__base) s
    cross join tillPostingDate tp
    left join other_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
inventory_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 13.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN inventory_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
inventory_values_raw as (
    select * from inventory_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from inventory_values_raw__base) s
    cross join tillPostingDate tp
    left join inventory_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
trade_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 16.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN trade_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
trade_values_raw as (
    select * from trade_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from trade_values_raw__base) s
    cross join tillPostingDate tp
    left join trade_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
cash_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 17.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN cash_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
cash_values_raw as (
    select * from cash_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from cash_values_raw__base) s
    cross join tillPostingDate tp
    left join cash_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_cash_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 18.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN other_cash_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
other_cash_values_raw as (
    select * from other_cash_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_cash_values_raw__base) s
    cross join tillPostingDate tp
    left join other_cash_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
current_investment_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 15.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN current_investment_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
current_investment_values_raw as (
    select * from current_investment_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from current_investment_values_raw__base) s
    cross join tillPostingDate tp
    left join current_investment_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_current_values_raw__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 20.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN other_current_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
other_current_values_raw as (
    select * from other_current_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_current_values_raw__base) s
    cross join tillPostingDate tp
    left join other_current_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
equity_share_values_raw__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 12.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN equity_share_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
equity_share_values_raw as (
    select * from equity_share_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from equity_share_values_raw__base) s
    cross join tillPostingDate tp
    left join equity_share_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
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
short_term_values_raw_base__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 38.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN short_term_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
short_term_values_raw_base as (
    select * from short_term_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from short_term_values_raw_base__base) s
    cross join tillPostingDate tp
    left join short_term_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_short_term_provision as (
select -round(COALESCE(sum(amount), 0), 5) as amount  , asat , 'Other short term provision Payables' as extra ,
'Sundary Creditor -Provision Creditor' as group_name ,
'113960' as accno ,  38.0::DOUBLE as srno from machineryVendorPayableResult where vendorPostiongGroup = 'PROVISION CREDITOR' group by asat , extra , group_name , accno , srno   
),
short_term_values_raw as (
  select * from short_term_values_raw_base 
  UNION ALL  
  select * from other_short_term_provision 
),
income_tax_values_raw__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 39.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN income_tax_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
income_tax_values_raw as (
    select * from income_tax_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from income_tax_values_raw__base) s
    cross join tillPostingDate tp
    left join income_tax_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
long_term_values_raw__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 28.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN long_term_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
long_term_values_raw as (
    select * from long_term_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from long_term_values_raw__base) s
    cross join tillPostingDate tp
    left join long_term_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
deferred_tax_values_raw__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 29.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN deferred_tax_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
deferred_tax_values_raw as (
    select * from deferred_tax_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from deferred_tax_values_raw__base) s
    cross join tillPostingDate tp
    left join deferred_tax_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_equity_values_raw__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 23.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN other_equity_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
other_equity_values_raw as (
    select * from other_equity_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_equity_values_raw__base) s
    cross join tillPostingDate tp
    left join other_equity_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
non_current_lease_values_raw__base as (
  select  round(-sum(x.amount), 5) as amount, x.asat as asat , la.bifercation as extra ,  x.Name as group_name , x.No as accno , 27.0::DOUBLE as srno
    from (
       select amount , asat , Name , No FROM gl_base
      ) as x
     INNER JOIN non_current_lease_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
     group by x.asat , x.Name , x.No , la.bifercation
),
non_current_lease_values_raw as (
    select * from non_current_lease_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from non_current_lease_values_raw__base) s
    cross join tillPostingDate tp
    left join non_current_lease_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
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
advance_to_creditors as (
SELECT -round(sum(AR),5) as amount, asat , vendorPostiongGroup as posting_group ,'Advances to Creditors' as extra FROM (
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
    WHERE customerTotal < 0
  )
  WHERE vendorPostiongGroup in ('CONSUMABLE','IMPORT CONSUMABLE','SERVICES IMPORT','EPC RM','IMPORT RM','MODULE RM','SERVICES')
  GROUP BY asat , vendorPostiongGroup
),
advance_to_capex_creditors as (
SELECT -round(sum(AR),5) as amount, asat , vendorPostiongGroup as posting_group ,'Advances to Capex Creditors' as extra FROM (
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
    WHERE customerTotal < 0
  )
  WHERE vendorPostiongGroup in ('DOMESTICS MACHINARY', 'IMPORT MACHINERY')
  GROUP BY asat , vendorPostiongGroup
),
machineryVendorAdvanceResult__base AS (
   select x.* EXCLUDE(posting_group) , gg.*EXCLUDE(posting_group) , 19.0::DOUBLE as srno  from (
     select * from advance_to_creditors
     union all
     select * from advance_to_capex_creditors
    ) x
    INNER JOIN
    gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
machineryVendorAdvanceResult as (
    select * from machineryVendorAdvanceResult__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from machineryVendorAdvanceResult__base) s
    cross join tillPostingDate tp
    left join machineryVendorAdvanceResult__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
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
loans_values_raw_base__base as (
    select  round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 19.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN loans_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
loans_values_raw_base as (
    select * from loans_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from loans_values_raw_base__base) s
    cross join tillPostingDate tp
    left join loans_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
loans_values_raw as (
    select *  from loans_values_raw_base 
    UNION ALL
    select * from machineryVendorAdvanceResult 
),
long_term_borrowing_values_raw_base__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 26.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN long_term_borrowing_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
long_term_borrowing_values_raw_base as (
    select * from long_term_borrowing_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from long_term_borrowing_values_raw_base__base) s
    cross join tillPostingDate tp
    left join long_term_borrowing_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
long_term_borrowing_values_raw as (
   select * from  long_term_borrowing_values_raw_base
   UNION ALL 
   (select 0 as amount , tillPostingDate.agedAsOf::Date as asat , 'Loans from Financial institution' as extra , 'Other Unsecured Loans' as group_name , 110600 as accno , 26.0::DOUBLE as srno  from tillPostingDate) 
   union all
   (select amount , asat , 'Loan Master Secured Deduction' as extra , '-' group_name , '-' accno, 26.0::DOUBLE as srno from secured_loan_next12_values_raw)  
),
short_term_borrowing_values_raw_base__base as (
    select  round(-sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 32.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN short_term_borrowing_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
short_term_borrowing_values_raw_base as (
    select * from short_term_borrowing_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from short_term_borrowing_values_raw_base__base) s
    cross join tillPostingDate tp
    left join short_term_borrowing_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
short_term_borrowing_values_raw as (
  select * from short_term_borrowing_values_raw_base 
  union all 
  ( select amount , asat , 'Loan Master Secured Addition' as extra , '-' group_name , '-' accno, 32.0::DOUBLE as srno from secured_loan_next12_values_raw
  )
),
micro_trade_values_raw_base__base as (
  select  round(-sum(amount), 5) as amount, asat as asat,'CHART OF ACCOUNT' as extra ,
            Name  as group_name  , No as accno,36.0::DOUBLE as srno
    FROM gl_base
    where 1=1
      and cast(No as varchar) in (select distinct cast(accno as varchar) from micro_trade_accounts)
      and :APPLY_FILTER:globaldimension1code:
    group by  asat , Name , No
),
micro_trade_values_raw_base as (
    select * from micro_trade_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from micro_trade_values_raw_base__base) s
    cross join tillPostingDate tp
    left join micro_trade_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),
other_current_liabilites_values_raw_base__base as (
    select  -round(sum(x.amount), 5) as amount, x.asat as asat, la.bifercation as extra ,
            x.Name as group_name , x.No as accno, 37.0::DOUBLE as srno
      from (
            select amount , asat , Name , No FROM gl_base
        ) as x
      INNER JOIN other_current_liabilites_accounts as la ON cast(x.No as varchar) = cast(la.accno as varchar)
    group by  x.asat , x.Name , x.No , la.bifercation
),
other_current_liabilites_values_raw_base as (
    select * from other_current_liabilites_values_raw_base__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_current_liabilites_values_raw_base__base) s
    cross join tillPostingDate tp
    left join other_current_liabilites_values_raw_base__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
),

-- ── ECL/ADV provisioning chain (brought over from query2 to feed trade_values) ─
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
query1_result AS (
   select x.*EXCLUDE(posting_group) , gg.*EXCLUDE(posting_group) , 37.0::DOUBLE as srno  from (
      SELECT -round(sum(AR),5) as amount, asat , customerPostingGroup as posting_group ,'Advances from customers ' as extra  
    FROM (
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
        WHERE customerTotal < 0
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    )
    WHERE lower(customerPostingGroup) IN (
        'epc commercial', 'epc govt project', 'epc ground mounted', 'epc roof top',
        'module domestic', 'module foreign', 'epc scrap', 'suspense'
    )
    GROUP BY asat , extra , posting_group , customerPostingGroup
    ) x
    INNER JOIN 
    gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group)) 
)
,
query2_result AS (
    SELECT round(COALESCE(sum(AR),0),5) AS amount, asat , customerPostingGroup as posting_group ,
    'Unsecured & Considered Good' as extra 
    FROM (
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
        WHERE customerTotal > 0
        GROUP BY customerNum, customerPostingGroup, ageGroup, customerName,
                 responsiblePerson, avgDueDaysSince, avgDueDaysSinceDue, color, asat
    )
    WHERE TRIM(customerPostingGroup) IN (
       'LC DOMESTIC' , 'MODULE DOMESTIC', 'MODULE FOREIGN', 'MODULE JOB' , 'EPC GOVT PROJECT' ,'EPC ROOF TOP' ,'EPC COMMERCIAL', 'EPC GROUND MOUNTED', 'EPC SCRAP', 'SUSPENSE' 
    )
    GROUP BY asat, customerPostingGroup , extra 
)
,
q2_final__base AS (
     select x.* EXCLUDE(posting_group) , gg.*EXCLUDE(posting_group) , 16.0::DOUBLE as srno  from (
       select * from query2_result
    ) x
    INNER JOIN
    gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
q2_final as (
    select * from q2_final__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from q2_final__base) s
    cross join tillPostingDate tp
    left join q2_final__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
other_current_liabilites_payable as (
  select  -round(sum(amount), 5) as amount  , asat , 'Other current liabilities Payables' as extra , 
  'Sundry Creditor - Expenses' as group_name , '113200' as accno , 37.0::DOUBLE as srno from  machineryVendornetResult where vendorPostiongGroup = 'EXPENSES'    
  group by asat , group_name , accno , srno 
),
creditors_for_capex as (
select -round(sum(amount), 5) as amount , asat , 'Creditors for Capex' as extra , 'Sundry Creditor - Domestics Machinary' as group_name , '112400' as accno , 37.0::DOUBLE as srno from machineryVendorPayableResult where vendorPostiongGroup =  'DOMESTICS MACHINARY'  group by asat , extra
union all 
select -round(sum(amount), 5) as amount , asat , 'Creditors for Capex' as extra , 
'Sundry Creditor - Import Machinery' as group_name , '111800' as accno , 37.0::DOUBLE as srno  
from machineryVendorPayableResult where vendorPostiongGroup =  'IMPORT MACHINERY'  group by asat , extra
)
,
other_current_liabilites_values_raw__base as (
  select *  from other_current_liabilites_values_raw_base
  union all
  select * from  query1_result
  union all
  select * from other_current_liabilites_payable
  union all
  select * from creditors_for_capex
),
other_current_liabilites_values_raw as (
    select * from other_current_liabilites_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_current_liabilites_values_raw__base) s
    cross join tillPostingDate tp
    left join other_current_liabilites_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
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
other_trade_values_raw__base as (
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
),
other_trade_values_raw as (
    select * from other_trade_values_raw__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from other_trade_values_raw__base) s
    cross join tillPostingDate tp
    left join other_trade_values_raw__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
micro_temp__base as (
 select x.* EXCLUDE(posting_group) , gg.*EXCLUDE(posting_group) , 36.0::DOUBLE as srno  from (
      select round(sum(AR),5) as amount,  asat , vendorPostiongGroup as posting_group , '' as extra from (
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
    WHERE customerTotal > 0 and customernum in (select distinct vendorno from non_msme) and vendorPostiongGroup 
     in ('IMPORT RM' , 'MODULE RM' ,'EPC RM', 'SERVICES' , 'LC FOREIGN' , 'CONSUMABLE' , 'IMPORT CONSUMABLE' , 'SERVICES IMPORT' ,'CONTRACT CREDITOR')
    ) group by asat , vendorPostiongGroup
              
    ) x
    INNER JOIN
    gl_groups as gg ON lower(TRIM(x.posting_group)) = lower(TRIM(gg.posting_group))
),
micro_temp as (
    select * from micro_temp__base
    union all
    select 0 as amount, tp.agedAsOf::Date as asat, s.extra as extra, s.group_name as group_name, s.accno as accno, s.srno as srno
    from (select distinct accno, extra, group_name, srno from micro_temp__base) s
    cross join tillPostingDate tp
    left join micro_temp__base r on r.accno = s.accno and r.asat = tp.agedAsOf::Date
    where r.asat is null
)
,
micro_trade_values_raw as (
select * from micro_trade_values_raw_base
union all
select * from micro_temp
),
trade_values as (
select * from q2_final 
union all   
select * from trade_values_raw
)
-- ── _value CTEs: per-partition fallback ────────────────────────────────────
select * from (
select * from other_trade_values_raw
union all
select * from micro_trade_values_raw
union all
select * from loans_values_raw
union all
select * from short_term_values_raw
union all
select * from other_current_liabilites_values_raw
  union all
  select * from trade_values
  union all
  select * from ppe_value_raw
  union all
  select * from cwp_value_raw
  union all
  select * from rtu_value_raw
  union all
  select * from intangbile_value_raw
  union all
  select * from non_current_values_raw
  union all
  select * from other_values_raw
  union all
  select * from inventory_values_raw
  union all
  select * from cash_values_raw
  union all
  select * from other_cash_values_raw
  union all
  select * from current_investment_values_raw
  union all
  select * from other_current_values_raw
  union all
  select * from equity_share_values_raw
  union all
  select * from other_equity_values_raw
  union all
  select * from long_term_borrowing_values_raw
  union all
  select * from long_term_values_raw
  union all
  select * from deferred_tax_values_raw
  union all
  select * from short_term_borrowing_values_raw
  union all
  select * from income_tax_values_raw
  union all 
  select * from non_current_lease_values_raw
)
where srno::DECIMAL(11,1)::VARCHAR =  :APPLY_DRILL_FILTER:srno:
