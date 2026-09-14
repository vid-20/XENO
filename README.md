# Comm-Log Send Reconciliation — merchant_id 501, October 2026

Finance's reported `target_base` for this merchant/month is **22**. This repo
reconciles that number from the raw campaign and send-log data.

## Contents

```
comm-log-reconciliation/
├── README.md            (this file)
├── RECONCILIATION.md    the bridge, the reasoning, what surprised me
├── sql/
│   └── target_base.sql  final query, returns 22
└── data/
    ├── comm_log.db
    ├── campaign.csv
    └── communication_log.csv
```

Start with `RECONCILIATION.md` if you want the full story — it walks through
the naive count (30), what I found wrong with it, and how I got down to 22.

## Running the query

**SQLite CLI:**

```bash
sqlite3 data/comm_log.db < sql/target_base.sql
```

Output should be:

```
chain_distinct_customers|standalone_events|target_base
15|7|22
```

**Or with Python, if sqlite3 isn't installed:**

```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('data/comm_log.db')
sql = open('sql/target_base.sql').read()
for row in conn.execute(sql):
    print(row)
"
```

```
(15, 7, 22)
```

## Checking the intermediate steps

Not needed to get the final answer, but useful if you want to confirm the
bridge is real and not just backfilled to match 22.

Naive count, should be 30:

```bash
sqlite3 data/comm_log.db "
SELECT COUNT(*) FROM communication_log
WHERE merchant_id = 501 AND communication_type = '2'
AND sent_time >= '2026-10-01' AND sent_time < '2026-11-01';
"
```

After dropping the unapproved campaign (9004), should be 26:

```bash
sqlite3 data/comm_log.db "
SELECT COUNT(*)
FROM communication_log cl
JOIN campaign c ON c.id = cl.communication_id
WHERE cl.merchant_id = 501
  AND cl.communication_type = '2'
  AND cl.sent_time >= '2026-10-01' AND cl.sent_time < '2026-11-01'
  AND c.creation_status IN ('approved','aborted','resumed','stopped')
  AND c.processing_status = 'processed';
"
```

Row count vs distinct customers per campaign, to see where the dedup actually
kicks in:

```bash
sqlite3 data/comm_log.db "
SELECT c.id, COUNT(*) AS rows_, COUNT(DISTINCT cl.customer_id) AS distinct_customers
FROM communication_log cl JOIN campaign c ON c.id = cl.communication_id
GROUP BY c.id ORDER BY c.id;
"
```

| campaign id | rows | distinct customers |
|---|---|---|
| 9001 | 10 | 10 |
| 9002 | 2 | 2 |
| 9003 | 1 | 1 |
| 9004 | 4 | 4 |
| 9101 | 7 | 6 |
| 9201 | 5 | 5 |
| 9202 | 1 | 1 |

9101 is the odd one — 7 rows but only 6 distinct customers, because C20 got
sent to twice. But 9101 has no parent and nothing retries off it, so it's
standalone, and the row count (7) is what actually gets used, not 6.


