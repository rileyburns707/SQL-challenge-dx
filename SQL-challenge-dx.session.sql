-- CTE: FilteredSquads
-- This CTE identifies all descendant snapshot squad IDs that fall under the specified parent hierarchies (57103 and 57101)
WITH FilteredSquads AS (
    SELECT
        ssh.descendant_id AS squad_id
    FROM
        snapshot_squad_hierarchies ssh
    WHERE
        -- Filter by ancestor IDs to include all their descendants. These IDs represent the target hierarchy branches
        ssh.ancestor_id IN (57103, 57101)
)
-- Main Query: Retrieves detailed sentiment scores and hierarchical information for snapshot squads.
SELECT
    ss.id AS snapshot_squad_id,
    ss.name AS snapshot_squad_name,
    -- Concatenates the names of parent, grandparent, and great-grandparent squads into a single hierarchy string, using ' > ' as a separator 
    -- CONCAT_WS handles NULL values, preventing extra separators
    CONCAT_WS(' > ',
              ss_great_grandparent.name,
              ss_grandparent.name,
              ss_parent.name
    ) AS parents,
    -- Calculates the sentiment score as the percentage of respondents who gave a value of 3 (good)
    -- NULLIF prevents division by zero if no responses are recorded for a squad/factor
    (COUNT(CASE WHEN sri.value = 3 THEN 1 END) * 100.0) / NULLIF(COUNT(sri.value), 0) AS percent_marked_3,
    -- Counts the number of responses for each sentiment value (1: bad, 2: so-so, 3: good)
    COUNT(CASE WHEN sri.value = 1 THEN 1 END) AS one_count,
    COUNT(CASE WHEN sri.value = 2 THEN 1 END) AS two_count,
    COUNT(CASE WHEN sri.value = 3 THEN 1 END) AS three_count,
    -- Counts the total number of unique users associated with survey requests for the squad
    COUNT(DISTINCT sreq.user_id) AS team_size,
    -- Retrieves the ID and name of the survey factor being analyzed
    MAX(f.id) AS factor_id,
    MAX(f.name) AS factor_name,
    -- Fetches benchmark percentiles (50th, 75th, 90th) for the specific factor from the default benchmark segment (benchmark_segments.id = 1)
    -- MAX() is used here because these values are constant per factor/benchmark segment within each group
    MAX(bf.p_50) AS p_50,
    MAX(bf.p_75) AS p_75,
    MAX(bf.p_90) AS p_90
FROM
    -- Primary table: snapshot_squads, representing the frozen team hierarchy at survey time
    snapshot_squads ss
-- Self-joins to retrieve names of hierarchical parents
-- LEFT JOIN ensures squads without parents at a given level are still included
LEFT JOIN
    snapshot_squads ss_parent ON ss.parent_id = ss_parent.id
LEFT JOIN
    snapshot_squads ss_grandparent ON ss_parent.parent_id = ss_grandparent.id
LEFT JOIN
    snapshot_squads ss_great_grandparent ON ss_grandparent.parent_id = ss_great_grandparent.id
-- Joins to link snapshot squads to the overarching survey snapshot
LEFT JOIN
    snapshots s ON ss.snapshot_id = s.id
-- Joins to link snapshot squads to individual survey requests made to team members
LEFT JOIN
    snapshot_requests sreq ON ss.id = sreq.snapshot_squad_id
-- Joins to link survey requests to actual submitted responses
LEFT JOIN
    snapshot_responses sr ON sreq.snapshot_response_id = sr.id
-- Joins to link survey responses to individual response items for each factor
LEFT JOIN
    snapshot_response_items sri ON sr.id = sri.snapshot_response_id
-- Joins to retrieve factor details
LEFT JOIN
    factors f ON sri.factor_id = f.id
-- Joins to retrieve benchmark data for factors
LEFT JOIN
    benchmark_factors bf ON f.id = bf.factor_id
-- Joins to filter by specific benchmark segments
LEFT JOIN
    benchmark_segments bs ON bf.benchmark_segment_id = bs.id
WHERE
    -- Filters the results to a specific snapshot
    ss.snapshot_id = 2849
    -- Filters to a specific survey factor 
    AND f.id = 223
    -- Filters to a specific benchmark segment
    AND bs.id = 1
    -- Filters by the overall account
    AND s.account_id = 1726
    -- Hierarchical Inclusion Filter:
    -- Only includes squads that are descendants of the specified parent IDs (57103, 57101).
    -- This leverages the FilteredSquads CTE to get all descendants.
    AND ss.id IN (SELECT squad_id FROM FilteredSquads)
    -- Hierarchical Exclusion Filter:
    -- Excludes any squads that are descendants of the "Data Engineering" (55395 or "Product & Data Platform" (57102) hierarchies
    AND ss.id NOT IN (
        SELECT ssh_exclude.descendant_id
        FROM snapshot_squad_hierarchies ssh_exclude
        WHERE ssh_exclude.ancestor_id IN (
            55395, -- Data Engineering Squad ID
            57102  -- Product & Data Platform Squad ID
        )
    )
GROUP BY
    -- Groups results by unique snapshot squad to aggregate metrics for each team
    ss.id,
    ss.name,
    ss_parent.name,
    ss_grandparent.name,
    ss_great_grandparent.name
ORDER BY
    -- Orders the final report alphabetically by snapshot squad name for readability.
    ss.name;