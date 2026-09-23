# Google Data Analytics lifecycle to face the needs

- PLN-4: Apply the Google Data Analytics lifecycle (Ask, Prepare, Process, Analyze, Share, Act) to structure the analytical problem-solving approach.

## Ask 
The user have two specific needs, and a third one which is exploratory. 

1. Is the MQL growth story real? Support your answer with numbers.
2. Where should the $1.5M go, and what should stop? Name programs and dollar amounts.
3. How confident are you, and what would change your mind?

To answer the first a funnel of the conversion rate between quarters will support the status and further decisions. 
To answer the second one, we need to address the rate conversion and be able to track the spend per provider over the quarters to understand how some specific have been growing. 
The exploratory question could address on the 


## Prepare 

The data needed is loaded into snowflake tables: 

- stg_mkt_lead
- stg_sfdc_account
- stg_mkt_campaign
- stg_mkt_touchpoint
- stg_sfdc_opportunity

Needed work models derived from the analysis will be stored with the prefix wrK_ and the final models to support the recommendations will be under the preffix pub. 

## Process

1. Profile the data before you trust it

- 01 Data profiling  - Referential integrity.sql
    - Not critical findings, all the entities contains a unique not null primary key. 
- 01 Data profiling - Entity Integrity
    - Join between MKT_LEAD and MKT_CAMPAIGN without findings, all the leads are linked to a campaign
    - Join between MKT_TOUCHPOINT and MKT_CAMPAIGN without findings, all the interactions are linked to a campaign
    - Join between MKT_TOUCHPOINT and STG_MKT_LEAD without findings, all the interactions are linked to a lead
    - Join between SFDC_OPPORTUNITY and MKT_LEAD, only 80% of the opportunities are linked to a lead
    - Join betwee STG_SFDC_ACCOUNT and STG_SFDC_OPPORTUNITY: 
      - Parent Table (SFDC_ACCOUNT): Acts as the master entity. It holds the primary key (account_id), meaning every row is a unique company or organization.
      - SFDC_OPPORTUNITY): Holds the foreign key (account_id) pointing back to the account. Because multiple opportunities can belong to a single account, the foreign key lives here, not on the account table.
      - The 20% "Unlinked": These represent accounts that exist in the CRM database as prospects or clients, but have never had a commercial deal/opportunity opened against them yet.

## Analyze

2. Write the SQL you would run

   
3. Answer Priya's three questions

## Share

4. Package the results either as STREAMLIT DASHBOARD or DECK.
 
Send the artifacts. 