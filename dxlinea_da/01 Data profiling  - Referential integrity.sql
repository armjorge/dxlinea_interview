
-- Referenctial integrity 

--When a lead actually has a campaign_id, does that campaign actually exist in the campaign table?" - Yes 

SELECT 
    COUNT(*) AS total_leads,
    COUNT(c.campaign_id) AS linked_leads,
    COUNT(*) - COUNT(c.campaign_id) AS unlinked_leads,
    ROUND(100.0 * COUNT(c.campaign_id) / COUNT(*), 2) AS pct_linked,
    ROUND(100.0 * (COUNT(*) - COUNT(c.campaign_id)) / COUNT(*), 2) AS pct_unlinked
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_LEAD l
LEFT JOIN DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_CAMPAIGN c
    ON l.source_campaign_id = c.campaign_id;

-- Referential integrity between mkt_lead and mkt_campaign is 100% clean—there are zero orphan leads pointing to non-existent campaigns.
-- 3 of the 326 campaigns generated zero leads. This is a critical finding.



--When an interaction actually has a campaign_id, does that campaign actually exist in the campaign table?" - Yes 
SELECT 
    COUNT(*) AS total_interactions,
    COUNT(c.campaign_id) AS linked_interactins,
    COUNT(*) - COUNT(c.campaign_id) AS unlinked_interactions,
    ROUND(100.0 * COUNT(c.campaign_id) / COUNT(*), 2) AS pct_linked,
    ROUND(100.0 * (COUNT(*) - COUNT(c.campaign_id)) / COUNT(*), 2) AS pct_unlinked
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_TOUCHPOINT touch
LEFT JOIN DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_CAMPAIGN c
    ON touch.campaign_id = c.campaign_id;

--When an interaction actually has a lead_id, does that campaign actually exist in the campaign table?" - Yes 

SELECT 
    COUNT(*) AS total_interactions,
    COUNT(l.lead_id) AS linked_lead,
    COUNT(*) - COUNT(l.lead_id) AS unlinked_leads,
    ROUND(100.0 * COUNT(l.lead_id) / COUNT(*), 2) AS pct_linked,
    ROUND(100.0 * (COUNT(*) - COUNT(l.lead_id)) / COUNT(*), 2) AS pct_unlinked
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_TOUCHPOINT touch
LEFT JOIN DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_LEAD l
    ON touch.lead_id = l.lead_id;


-- When an opportunity actually has a lead_id, does that lead actually exist in the lead table?" - No, apparently only 80% is being linked

SELECT 
    COUNT(*) AS total_interactions,
    COUNT(l.lead_id) AS linked_lead,
    COUNT(*) - COUNT(l.lead_id) AS unlinked_leads,
    ROUND(100.0 * COUNT(l.lead_id) / COUNT(*), 2) AS pct_linked,
    ROUND(100.0 * (COUNT(*) - COUNT(l.lead_id)) / COUNT(*), 2) AS pct_unlinked
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_SFDC_OPPORTUNITY op
LEFT JOIN DXLINEA_INTERVIEW.RAW_DXLINEA.STG_MKT_LEAD l
    ON op.source_lead_id = l.lead_id;

    

SELECT 
DISTINCT OPPORTUNITY_TYPE
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_SFDC_OPPORTUNITY LIMIT 50; 
    

SELECT 
OPPORTUNITY_TYPE
,COUNT(SOURCE_LEAD_ID)
,COUNT(PRIMARY_CAMPAIGN_ID),
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_SFDC_OPPORTUNITY 
GROUP BY OPPORTUNITY_TYPE;
LIMIT 50; 


-- When an account actually has a account_id, does that can be tracked back to the opportunity table?" - No, apparently only 80% is being linked

SELECT 
    COUNT(*) AS total_interactions,
    COUNT(op.account_id) AS linked_lead,
    COUNT(*) - COUNT(op.account_id) AS unlinked_leads,
    ROUND(100.0 * COUNT(op.account_id) / COUNT(*), 2) AS pct_linked,
    ROUND(100.0 * (COUNT(*) - COUNT(op.)) / COUNT(*), 2) AS pct_unlinked
FROM DXLINEA_INTERVIEW.RAW_DXLINEA.STG_SFDC_ACCOUNT sa
LEFT JOIN DXLINEA_INTERVIEW.RAW_DXLINEA.STG_SFDC_OPPORTUNITY op
    ON sa.account_id = op.account_id;


-- The Parent Table (STG_SFDC_ACCOUNT): Acts as the master entity. It holds the primary key (account_id), meaning every row is a unique company or organization.
-- The Child Table (STG_SFDC_OPPORTUNITY): Holds the foreign key (account_id) pointing back to the account. Because multiple opportunities can belong to a single account, the foreign key lives here, not on the account table.

--The 20% "Unlinked": These represent accounts that exist in the CRM database as prospects or clients, but have never had a commercial deal/opportunity opened against them yet.

