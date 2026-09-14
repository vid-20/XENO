# Comm-Log Send Reconciliation — merchant_id = 501, October 2026

Target: Finance's `target_base` = **22**

## Reconciliation bridge

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive count: `SELECT COUNT(*) FROM communication_log WHERE merchant_id=501 AND communication_type='2' AND sent_time` in Oct 2026 | **30** | Starting point — every send-attempt row, no adjustments. |
| 1 | Drop rows belonging to campaign `9004` (`creation_status = 'approval_awaiting'`) | **26** | Checked `campaign.creation_status` and found 9004 never cleared approval. Per the data dictionary, an unapproved campaign doesn't count toward reported sends even though its `communication_log` rows already exist (send pipeline ran ahead of approval bookkeeping). This removes 4 rows (C11–C14). |
| 2 | Within retry chains, collapse repeat attempts on the same customer down to one — i.e. count **distinct customers per chain**, not per row | **22** | Noticed campaign `9002`/`9003` share `parent_id` back to `9001` (chain A), and `9202` points to `9201` (chain B). These are the *same underlying communication*, re-attempted. Chain A: 13 raw rows → 10 distinct customers (C1–C10), saving 3. Chain B: 6 raw rows → 5 distinct customers (D1–D5), saving 1. Total saving: 4. |
| **final** | | **22** | Matches Finance's reported `target_base`. |

### Why standalone campaign 9101 was *not* deduplicated
Campaign `9101` has no `parent_id` and no other campaign points at it — it's a standalone communication, not a retry chain. Customer `C20` genuinely appears twice under it (Oct 10 and Oct 20), which the data dictionary explicitly calls out as a legitimate re-targeting event, distinct from a retry. So all 7 of its rows (C20 ×2, C21–C25 ×1 each) are counted as 7 separate events, not collapsed to 6. If I had applied the same "distinct customer" dedup rule everywhere instead of only within actual retry chains, I'd have landed on 21, one short of the target — which is what first tipped me off that dedup needs to be scoped to retry-linked families, not applied merchant/campaign-wide.

## Final SQL

See [`sql/target_base.sql`](sql/target_base.sql). It:
1. Walks `campaign.parent_id` recursively to find each campaign's ultimate chain root.
2. Groups campaigns into "families" sharing a root; families with >1 campaign are retry chains, families of exactly 1 are standalone.
3. Filters `communication_log` to only campaigns with `creation_status` in `('approved','aborted','resumed','stopped')` and `processing_status = 'processed'`.
4. For chain families: counts `DISTINCT (root_id, customer_id)`.
5. For standalone families: counts every row.
6. Sums the two.

Running it against `data/comm_log.db` returns `target_base = 22`.

## What surprised me

Two things weren't obvious from a first pass at the schema. First, `9004` has `processing_status = 'processed'` — meaning delivered `communication_log` rows exist for it — despite never clearing approval; a naive "just check `processing_status`" filter would have silently kept 4 sends that shouldn't count. Second, the two dedup rules that apply to the *same-looking* pattern (one customer, same `communication_id`, appearing more than once in the log) are opposite depending on whether the campaign is a retry-chain member or a standalone campaign: retry-chain repeats get collapsed, standalone repeats (like C20 under 9101) don't. Without cross-checking `campaign.parent_id` topology first, it's easy to apply one dedup rule uniformly and land on a number that's close but wrong (21 or 23, depending on which way you err) rather than exactly 22.
