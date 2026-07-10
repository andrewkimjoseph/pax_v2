SELECT
    date_trunc('day', e.evt_block_time + INTERVAL '3' HOUR) AS txn_date,
    SUM(CAST(e.value AS DOUBLE)) / 1e18 AS daily_total,
    SUM(SUM(CAST(e.value AS DOUBLE)) / 1e18) OVER (
        ORDER BY date_trunc('day', e.evt_block_time + INTERVAL '3' HOUR)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_total
FROM gooddollar_celo.supergooddollar_evt_transfer e
WHERE e.contract_address = 0x62B8B11039FcfE5aB0C56E502b1C372A3d2a9c7A
  AND e."from" = 0x4D167933D742B31229bc730eADf5f2E3c4feceA2
GROUP BY date_trunc('day', e.evt_block_time + INTERVAL '3' HOUR)
ORDER BY txn_date ASC