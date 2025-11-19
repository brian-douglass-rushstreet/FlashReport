--create or replace table FlashReport as
with patron_rating_slot as (
    SELECT count(DISTINCT(s.PTNID)) cardedslottrips,
          s.yyyyinserted, s.mminserted, s.ddinserted, 
           sum(s.TIMEONDEVSEC) AS cardedslotSec,
           sum(s.CASHBUYIN) AS cardedslotci,
           sum(s.TOTBUYIN)-sum(s.TOTWALKWITH) AS cardedslotgrosswin
           , s.Provider_abbr	
    FROM KCMS.VW_TAL_PTNRATING s	  
           INNER JOIN KCMS.VW_TAL_DEVICE d ON d.DEVID=s.devid 
           INNER JOIN KCMS.VW_TAL_GSTZONE z ON z.ZONEID=d.zoneid
    WHERE s.DEVTYPID IN (1,2)
        AND z.ZONENAME NOT IN ('ZONE W','WT')
        AND s.STATUS = 'CLOSED' 
        AND s.PTNID<>0
    GROUP BY 
        s.Provider_abbr,
        s.yyyyinserted, s.mminserted, s.ddinserted
),

patron_rating_table as (
    SELECT count(DISTINCT(t.PTNID)) cardedtabletrips,
          t.yyyyinserted, t.mminserted, t.ddinserted, 
           sum(t.TIMEONDEVSEC) AS cardedtablesec,
           sum(t.CASHBUYIN) AS cardedtabledrop,
           sum(t.TOTBUYIN)-sum(t.TOTWALKWITH) AS cardedtablegrosswin
           , t.Provider_abbr	
    FROM KCMS.VW_TAL_PTNRATING t	  
        INNER JOIN KCMS.VW_TAL_PATRON p ON p.PTNID=t.PTNID
    WHERE t.DEVTYPID IN (3)
        AND t.gameid NOT LIKE '5023'
        AND t.STATUS = 'CLOSED' 
        AND p.LASTNAME NOT LIKE 'Refused%'
        AND p.LASTNAME NOT LIKE 'Unknown%'
    GROUP BY t.Provider_abbr, t.yyyyinserted, t.mminserted, t.ddinserted
),

patron_rating_hybrid as (
    SELECT count(DISTINCT(h.PTNID)) cardedhybridtrips,
          h.yyyyinserted, h.mminserted, h.ddinserted, 
           sum(h.TIMEONDEVSEC) AS cardedhybridSec,
           sum(h.CASHBUYIN) AS cardedhybridcashdrop,
           sum(h.TOTBUYIN)-sum(h.TOTWALKWITH) AS cardedhybridwin
           , h.Provider_abbr	
    FROM KCMS.VW_TAL_PTNRATING h	  
           INNER JOIN KCMS.VW_TAL_DEVICE d ON d.DEVID=h.devid 
           INNER JOIN KCMS.VW_TAL_GSTZONE z ON z.zoneid=d.zoneid
    WHERE  h.DEVTYPID IN (1,2)
        AND z.ZONENAME IN ('ZONE W','WT') 
        AND h.STATUS = 'CLOSED' 
        AND h.PTNID<>0
    GROUP BY h.Provider_abbr, h.yyyyinserted, h.mminserted, h.ddinserted
),

patron_rating_carded as (
    SELECT  t.yyyyinserted, t.mminserted, t.ddinserted, 
          count(DISTINCT(t.PTNID)) cardedtotaltrips,
           sum(t.TIMEONDEVSEC) AS cardedtotalsec,
           sum(t.TOTBUYIN)-sum(t.TOTWALKWITH) AS cardedtotalgrosswin
           , t.Provider_abbr
    FROM KCMS.VW_TAL_PTNRATING t 
        INNER JOIN KCMS.VW_TAL_PATRON p ON p.PTNID=t.PTNID 
    WHERE t.DEVTYPID IN (1,2,3)
        AND t.STATUS = 'CLOSED'
        AND t.PTNID<>0
        AND p.LASTNAME NOT LIKE 'Refused%'
        AND p.LASTNAME NOT LIKE 'Unknown%'
    GROUP BY t.Provider_abbr, t.yyyyinserted, t.mminserted, t.ddinserted
),

daily_patron_all as (
    SELECT YEAR, MONTH, DAY,  
        sum(CASE WHEN gstid='43' THEN EPRUSED/800 + NONCASHABLEUSED ---PITT
                WHEN gstid='56' THEN EPRUSED/400 + NONCASHABLEUSED ---PHIL																					
                WHEN gstid='58' THEN EPRUSED/200 + NONCASHABLEUSED ---OHARE
                WHEN gstid='197' THEN EPRUSED/300 + NONCASHABLEUSED ----SCHE
                ELSE NULL END) AS allfspused,   		
    sum(CASE WHEN gstid='43' THEN EPRUSED/800
                WHEN gstid='56' THEN EPRUSED/400 																					
                WHEN gstid='58' THEN EPRUSED/200 
                WHEN gstid='197' THEN EPRUSED/300
                ELSE NULL END) AS eprused
    , Provider_abbr 
    FROM KCMS.VW_TAL_DAILYPTNALL 
    GROUP BY Provider_abbr, YEAR, MONTH, DAY
),

daily_patron_sum as (
    SELECT to_char(anndate,'yyyy') AS YEAR, 
        to_char(anndate,'mm') AS MONTH,
        to_char(anndate,'dd') AS DAY, 
        count(ptnid) newsignups
        , Provider_abbr
    FROM KCMS.VW_TAL_DAILYPTNSUM
    WHERE LASTNAME NOT LIKE 'Refused%'
        AND LASTNAME NOT LIKE 'Unknown%'
    GROUP BY Provider_abbr, to_char(anndate,'yyyy'), to_char(anndate, 'mm'), to_char(anndate, 'dd')
),

shift_table_stat as (
    SELECT YEAR, MONTH, "DAY",
        SUM(POSTEDDROP) + SUM(TBL_AUDIT_ADJ) + SUM(MARKER) + SUM(MARKER_ADJ) AS PROPTABLEDROP,
        (SUM(CLOSER)+SUM(CLOSER_ADJ)) -- closer 
        -(SUM(OPENER)+SUM(OPENER_ADJ)) -- minus opener
        +(SUM(CREDIT)+SUM(CREDIT_ADJ)) -- add credits
        -(SUM(FILL)+SUM(FILL_ADJ)) -- minus fills
        +SUM(POSTEDDROP) + SUM(TBL_AUDIT_ADJ) + SUM(MARKER) + SUM(MARKER_ADJ) --add drop
        -(SUM(TBLJP)+SUM(TBLJP_ADJ)) AS PROPTABLEGROSSWIN, 
        sum(posteddrop_other+posteddrop_other_adj) AS TABLEMPL
        , Provider_abbr
    FROM KCMS.VW_TAL_SHIFTTBLSTAT
    WHERE GAMEID NOT IN ('5023')
    GROUP BY Provider_abbr, YEAR, MONTH, "DAY" 
),

property_poker as (
    SELECT YEAR, MONTH, "DAY",
        (SUM(CLOSER)+SUM(CLOSER_ADJ)) -- closer 
        -(SUM(OPENER)+SUM(OPENER_ADJ)) -- minus opener
        +(SUM(CREDIT)+SUM(CREDIT_ADJ)) -- add credits
        -(SUM(FILL)+SUM(FILL_ADJ)) -- minus fills
        +SUM(POSTEDDROP) + SUM(TBL_AUDIT_ADJ) + SUM(MARKER) + SUM(MARKER_ADJ) --add drop
        -(SUM(TBLJP)+SUM(TBLJP_ADJ)) AS PROPPOKERWIN
        , Provider_abbr
    FROM KCMS.VW_TAL_SHIFTTBLSTAT
    WHERE GAMEID IN ('5023')
    GROUP BY Provider_abbr, YEAR, MONTH, "DAY" 
),

property_hybrid as (
    SELECT 	da."YEAR", da."MONTH", da."DAY",
            count(da.assetnum) hybridunits, 
            sum(coininamt)-sum(coinoutamt)-sum(metjp) prophybridwin, sum(estcashdrop) prophybridestcashdrop, sum(estcashdrop) hybridestdrop
            , da.Provider_abbr
    FROM KCMS.VW_TAL_DAILYDEVSTAT da
           INNER JOIN KCMS.VW_TAL_DEVICE d ON d.DEVID=da.devid 
           INNER JOIN KCMS.VW_TAL_GSTZONE z ON z.ZONEID=d.ZONEID 
    WHERE playcnt >0
        AND z.zonename IN ('ZONE W','WT')
    GROUP BY da.Provider_abbr, da."YEAR", da."MONTH", da."DAY"
),

final as (
    SELECT 
        ds.provider_abbr, 
        DATE_FROM_PARTS(ds.year, ds.month, ds.day) AS gamingday, 
        count(ds.assetnum) slotunits, 
        sum(coininamt) propslotci,  
        sum(coininamt)-sum(coinoutamt)-sum(metjp) propslotgrosswin, 
        sum(estcashdrop) propslotestcashdrop, 
        ifnull(splay.cardedslottrips,0) as cardedslottrips, 
        ifnull(splay.cardedslotsec,0) as cardedslotsec, 
        ifnull(splay.cardedslotci,0) as cardedslotci, 
        ifnull(splay.cardedslotgrosswin,0) as cardedslotgrosswin, 
        ifnull(fp.allfspused,0) as allfspused, 
        ifnull(fp.eprused,0) as eprused,
        ifnull(prop.proptabledrop,0) as proptabledrop, 
        ifnull(prop.proptablegrosswin,0) as proptablegrosswin, 
        ifnull(prop.tablempl,0) as tablempl, 
        ifnull(tplay.cardedtabletrips,0) as cardedtabletrips, 
        ifnull(tplay.cardedtablesec,0) as cardedtablesec, 
        ifnull(tplay.cardedtabledrop,0) as cardedtabledrop, 
        ifnull(tplay.cardedtablegrosswin,0) as cardedtablegrosswin,
        ifnull(hyb.hybridunits,0) as hybridunits, 
        ifnull(prophybridestcashdrop,0) as prophybridestcashdrop,  
        ifnull(prophybridwin,0) as prophybridwin,
        ifnull(hplay.cardedhybridtrips,0) as cardedhybridtrips, 
        ifnull(hplay.cardedhybridsec,0) as cardedhybridsec, 
        ifnull(hplay.cardedhybridcashdrop,0) as cardedhybridcashdrop, 
        ifnull(hplay.cardedhybridwin,0) as cardedhybridwin,
        ifnull(ttlplay.cardedtotaltrips,0) as cardedtotaltrips, 
        ifnull(ttlplay.cardedtotalsec,0) as cardedtotalsec, 
        ifnull(ttlplay.cardedtotalgrosswin,0) as cardedtotalgrosswin, 
        ifnull(proppokerwin,0) as proppokerwin,
        ifnull(newsignups,0) as newsignups
    FROM KCMS.VW_TAL_DAILYDEVSTAT ds
       INNER JOIN KCMS.VW_TAL_DEVICE d ON d.DEVID=ds.devid 
       INNER JOIN KCMS.VW_TAL_GSTZONE z ON z.ZONEID=d.ZONEID 

    ----CARDED SLOT
    LEFT OUTER JOIN (
        select * from patron_rating_slot
    ) splay ON (splay.Provider_abbr=ds.Provider_abbr and splay.yyyyinserted=ds.year AND splay.mminserted=ds.month AND splay.ddinserted=ds.day)

    ----CARDED TABLE
    LEFT OUTER JOIN (
        select * from patron_rating_table
    ) tplay ON (tplay.Provider_abbr=ds.Provider_abbr and tplay.yyyyinserted=ds.year AND tplay.mminserted=ds.month AND tplay.ddinserted=ds.day)

    ----CARDED HYBRID
    LEFT OUTER JOIN (
        select * from patron_rating_hybrid
    ) hplay ON (hplay.Provider_abbr=ds.Provider_abbr and hplay.yyyyinserted=ds.year AND hplay.mminserted=ds.month AND hplay.ddinserted=ds.day)

    ---CARDED ALL
    LEFT OUTER JOIN (
        select * from patron_rating_carded
    ) ttlplay ON (ttlplay.Provider_abbr=ds.Provider_abbr and ttlplay.yyyyinserted=ds.year AND ttlplay.mminserted=ds.month AND ttlplay.ddinserted=ds.day)

    ----FSP
    LEFT OUTER JOIN (
        select * from daily_patron_all
    ) fp ON (fp.Provider_abbr=ds.Provider_abbr and fp.year=ds.year AND fp.month=ds.month AND fp.day=ds.day)

    ---NEW SIGNUPS
    LEFT OUTER JOIN (
        select * from daily_patron_sum
    ) n ON (n.Provider_abbr=ds.Provider_abbr and n.year=ds.year AND n.month=ds.month AND n.day=ds.day)

    -----PROP TBL GAMES
    LEFT OUTER JOIN (
        select * from shift_table_stat
    ) prop ON (prop.Provider_abbr=ds.Provider_abbr and prop.YEAR=ds.YEAR AND prop.MONTH=ds.MONTH AND prop.DAY=ds.day)

    -----PROP POKER
    LEFT OUTER JOIN (
        select * from property_poker
    ) proppkr ON (proppkr.Provider_abbr=ds.Provider_abbr and proppkr.YEAR=ds.YEAR AND proppkr.MONTH=ds.MONTH AND proppkr.DAY=ds.day)

    ---PROP HHYBRID
    LEFT OUTER JOIN (
        select * from property_hybrid
    ) hyb ON (hyb.Provider_abbr=ds.Provider_abbr and hyb.YEAR=ds.YEAR AND hyb.MONTH=ds.MONTH AND hyb.DAY=ds.day)

    WHERE playcnt >=0
        AND z.zonename NOT IN ('ZONE W','WT')
        --AND ds.YEAR = 2021 
        --and ds.MONTH= 6
    GROUP BY 
        ds.Provider_abbr,
        DATE_FROM_PARTS(ds.year, ds.month, ds.day),
        splay.cardedslottrips, splay.cardedslotsec, splay.cardedslotci, splay.cardedslotgrosswin, fp.allfspused, fp.eprused,
        prop.proptabledrop, prop.proptablegrosswin, prop.tablempl, tplay.cardedtabletrips, tplay.cardedtablesec, tplay.cardedtabledrop, tplay.cardedtablegrosswin,
        hyb.hybridunits, prophybridestcashdrop, prophybridwin, hybridestdrop,
        hplay.cardedhybridtrips, hplay.cardedhybridsec, hplay.cardedhybridcashdrop, hplay.cardedhybridwin, 
        ttlplay.cardedtotaltrips, ttlplay.cardedtotalsec, ttlplay.cardedtotalgrosswin, proppokerwin, newsignups
    ORDER BY DATE_FROM_PARTS(ds.year, ds.month, ds.day)  ASC
)

--select * from patron_rating_slot
--select * from patron_rating_table
--select * from patron_rating_hybrid
--select * from patron_rating_carded
--select * from daily_patron_all
--select * from daily_patron_sum
--select * from shift_table_stat
--select * from property_poker
--select * from property_hybrid
select * from final 
--    where gamingday =  datefromparts('2021', '06', '18')
    where gamingday >= dateadd(day, -3, current_date())
        

