-- target_base reconciliation for merchant_id = 501, October 2026
-- Logic:
-- I group campaigns into families by tracing parent_id back to a root, drop any send rows from campaigns that were never approved, then count distinct customers within multi-campaign families (retry chains) but count every row as-is within single-campaign families (standalone campaigns), and add the two together.
WITH RECURSIVE root_finder(id, root_id) AS (
    SELECT id, id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, rf.root_id
    FROM campaign c
    JOIN root_finder rf ON c.parent_id = rf.id
),

family_size AS (
    SELECT root_id, COUNT(*) AS n
    FROM root_finder
    GROUP BY root_id
),

eligible AS (
    SELECT c.id, rf.root_id, fs.n AS family_size
    FROM campaign c
    JOIN root_finder rf   ON rf.id = c.id
    JOIN family_size fs   ON fs.root_id = rf.root_id
    WHERE c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND c.processing_status = 'processed'
),

tagged AS (
    SELECT cl.customer_id, e.root_id, e.family_size
    FROM communication_log cl
    JOIN eligible e ON e.id = cl.communication_id
    WHERE cl.merchant_id = 501
      AND cl.communication_type = '2'
      AND cl.sent_time >= '2026-10-01'
      AND cl.sent_time <  '2026-11-01'
)

SELECT
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT root_id, customer_id
        FROM tagged
        WHERE family_size > 1
    ))                                              AS chain_distinct_customers,
    (SELECT COUNT(*) FROM tagged WHERE family_size = 1) AS standalone_events,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT root_id, customer_id
        FROM tagged
        WHERE family_size > 1
    ))
    +
    (SELECT COUNT(*) FROM tagged WHERE family_size = 1) AS target_base;

-- Result: chain_distinct_customers = 15, standalone_events = 7, target_base = 22
