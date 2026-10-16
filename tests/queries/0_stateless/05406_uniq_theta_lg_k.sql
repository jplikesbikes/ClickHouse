-- Tags: no-fasttest
-- no-fasttest: uniqTheta needs datasketches, which fasttest does not build

-- The default and an explicit default agree, and the parameter is part of the state type.
SELECT uniqTheta(number) = uniqTheta(12)(number) FROM numbers(100000);
SELECT toTypeName(uniqThetaState(number)), toTypeName(uniqThetaState(16)(number)) FROM numbers(1);

-- Below 2^lg_k a sketch is exact, so 50000 distinct values are counted exactly at lg_k = 16 and not at the default.
SELECT uniqTheta(16)(number) FROM numbers(50000);
SELECT uniqTheta(number) != 50000 FROM numbers(50000);

-- Every way of constructing the state honours lg_k: string keys, the variadic path, and per-group states.
SELECT uniqTheta(16)(toString(number)) FROM numbers(50000);
SELECT uniqTheta(16)(number, number % 7) FROM numbers(50000);
SELECT toUInt8(number % 4) AS k, uniqTheta(16)(number) FROM numbers(50000) GROUP BY k ORDER BY k;

-- Out-of-range and surplus parameters are refused.
SELECT uniqTheta(4)(number) FROM numbers(1); -- { serverError ARGUMENT_OUT_OF_BOUND }
SELECT uniqTheta(27)(number) FROM numbers(1); -- { serverError ARGUMENT_OUT_OF_BOUND }
SELECT uniqTheta(16, 1)(number) FROM numbers(1); -- { serverError NUMBER_OF_ARGUMENTS_DOESNT_MATCH }

-- The precision survives storage and merges: the serialized sketch does not record k, the column type does.
-- Keyed on `k` rather than `tuple()`, because with an empty sorting key the merge combines parts but not rows.
DROP TABLE IF EXISTS theta_lg_k;
CREATE TABLE theta_lg_k (k UInt8, s AggregateFunction(uniqTheta(16), UInt64)) ENGINE = AggregatingMergeTree ORDER BY k;
INSERT INTO theta_lg_k SELECT 0, uniqThetaState(16)(number) FROM numbers(30000);
INSERT INTO theta_lg_k SELECT 0, uniqThetaState(16)(number) FROM numbers(20000, 30000);
OPTIMIZE TABLE theta_lg_k FINAL;
SELECT finalizeAggregation(s) FROM theta_lg_k;
SELECT uniqThetaMerge(16)(s) FROM theta_lg_k;
DROP TABLE theta_lg_k;

-- A small set inside a large one. The intersection inherits the large state's sampling rate, so lg_k on the large
-- side is what buys precision: ~1311 retained hashes at lg_k = 16 (2.8% relative standard error) against ~82 at the
-- default. Either argument order works, since the result fits the smaller state's k.
WITH
    (SELECT uniqThetaState(16)(number) FROM numbers(1000000)) AS big,
    (SELECT uniqThetaState(number * 50) FROM numbers(20000)) AS small
SELECT
    abs(finalizeAggregation(uniqThetaIntersect(big, small)) - 20000) < 2000,
    abs(finalizeAggregation(uniqThetaIntersect(small, big)) - 20000) < 2000,
    toTypeName(uniqThetaIntersect(big, small)),
    toTypeName(uniqThetaIntersect(small, big));
