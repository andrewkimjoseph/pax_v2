WITH canvassing_tagged_txns AS (
  SELECT
    block_time,
    block_number,
    hash,
    "from",
    "to"
  FROM celo.transactions
  WHERE bytearray_position(data, 43414e56415353494e47) > 0
    AND block_number >= 67800000
),

daily_counts AS (
  SELECT
    DATE_TRUNC('day', block_time) AS day,
    COUNT(*) AS txn_count
  FROM canvassing_tagged_txns
  GROUP BY 1
),

daily_with_cumulative AS (
  SELECT
    day,
    txn_count,
    SUM(txn_count) OVER (ORDER BY day ASC) AS cumulative_txns
  FROM daily_counts
)

SELECT
  d.day,
  d.txn_count,
  d.cumulative_txns,
  t.hash,
  t.block_time,
  t.block_number,
  t."from",
  t."to"
FROM daily_with_cumulative d
LEFT JOIN canvassing_tagged_txns t ON DATE_TRUNC('day', t.block_time) = d.day
ORDER BY t.block_time DESC