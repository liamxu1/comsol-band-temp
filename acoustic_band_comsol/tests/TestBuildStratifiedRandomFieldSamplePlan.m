function tests = TestBuildStratifiedRandomFieldSamplePlan
tests = functiontests(localfunctions);
end

function testProducesOneSamplePerBlock(testCase)
cfg = struct( ...
    'field_sampling_mode', 'stratified_random', ...
    'field_sample_count', 50, ...
    'field_sample_k_bins', 10, ...
    'field_sample_band_bins', 5);

plan = BuildStratifiedRandomFieldSamplePlan(51, 10, cfg);

verifyEqual(testCase, plan.sample_count, 50);
verifySize(testCase, plan.selection_ik, [50, 1]);
verifySize(testCase, plan.selection_ib, [50, 1]);
verifySize(testCase, unique([plan.block_k_index, plan.block_band_index], 'rows'), [50, 2]);
verifyTrue(testCase, all(plan.selection_ik >= 1 & plan.selection_ik <= 51));
verifyTrue(testCase, all(plan.selection_ib >= 1 & plan.selection_ib <= 10));
end

function testRejectsBinProductMismatch(testCase)
cfg = struct( ...
    'field_sampling_mode', 'stratified_random', ...
    'field_sample_count', 50, ...
    'field_sample_k_bins', 9, ...
    'field_sample_band_bins', 5);

verifyError(testCase, @() BuildStratifiedRandomFieldSamplePlan(51, 10, cfg), ...
    'BuildStratifiedRandomFieldSamplePlan:InvalidBinProduct');
end
