function plan = BuildStratifiedRandomFieldSamplePlan(n_k, n_band, cfg)
%BUILDSTRATIFIEDRANDOMFIELDSAMPLEPLAN Partition a k-band grid and sample one per block.

mode = char(string(getConfigValue(cfg, 'field_sampling_mode', 'stratified_random')));
if ~strcmpi(mode, 'stratified_random')
    error('BuildStratifiedRandomFieldSamplePlan:UnsupportedMode', ...
        'Unsupported field sampling mode: %s', mode);
end

sample_count = resolvePositiveInteger(cfg, 'field_sample_count', 50);
k_bins = resolvePositiveInteger(cfg, 'field_sample_k_bins', 10);
band_bins = resolvePositiveInteger(cfg, 'field_sample_band_bins', 5);

if k_bins * band_bins ~= sample_count
    error('BuildStratifiedRandomFieldSamplePlan:InvalidBinProduct', ...
        ['cfg.field_sample_k_bins * cfg.field_sample_band_bins must equal ', ...
        'cfg.field_sample_count.']);
end
if k_bins > n_k
    error('BuildStratifiedRandomFieldSamplePlan:TooManyKBins', ...
        'cfg.field_sample_k_bins (%d) exceeds n_k (%d).', k_bins, n_k);
end
if band_bins > n_band
    error('BuildStratifiedRandomFieldSamplePlan:TooManyBandBins', ...
        'cfg.field_sample_band_bins (%d) exceeds n_band (%d).', band_bins, n_band);
end

k_ranges = buildContiguousRanges(n_k, k_bins, 'k');
band_ranges = buildContiguousRanges(n_band, band_bins, 'band');

plan = struct();
plan.sample_count = sample_count;
plan.k_bins = k_bins;
plan.band_bins = band_bins;
plan.sampling_mode = mode;
plan.selection_ik = zeros(sample_count, 1);
plan.selection_ib = zeros(sample_count, 1);
plan.selection_linear_index = zeros(sample_count, 1);
plan.block_k_index = zeros(sample_count, 1);
plan.block_band_index = zeros(sample_count, 1);
plan.k_block_ranges = zeros(k_bins, 2);
plan.band_block_ranges = zeros(band_bins, 2);

for i = 1:k_bins
    plan.k_block_ranges(i, :) = [k_ranges{i}(1), k_ranges{i}(end)];
end
for i = 1:band_bins
    plan.band_block_ranges(i, :) = [band_ranges{i}(1), band_ranges{i}(end)];
end

sample_index = 0;
for k_block = 1:k_bins
    k_candidates = k_ranges{k_block};
    for band_block = 1:band_bins
        band_candidates = band_ranges{band_block};
        sample_index = sample_index + 1;
        ik = k_candidates(randi(numel(k_candidates)));
        ib = band_candidates(randi(numel(band_candidates)));
        plan.selection_ik(sample_index) = ik;
        plan.selection_ib(sample_index) = ib;
        plan.selection_linear_index(sample_index) = sub2ind([n_k, n_band], ik, ib);
        plan.block_k_index(sample_index) = k_block;
        plan.block_band_index(sample_index) = band_block;
    end
end
end

function ranges = buildContiguousRanges(count, bin_count, axis_name)
edges = floor(linspace(0, count, bin_count + 1));
ranges = cell(bin_count, 1);
for i = 1:bin_count
    first_index = edges(i) + 1;
    last_index = edges(i + 1);
    if last_index < first_index
        error('BuildStratifiedRandomFieldSamplePlan:EmptyBlock', ...
            'The %s axis partition produced an empty block at index %d.', ...
            axis_name, i);
    end
    ranges{i} = first_index:last_index;
end
end

function value = resolvePositiveInteger(cfg, field_name, default_value)
value = getConfigValue(cfg, field_name, default_value);
value = double(value);
if ~isscalar(value) || ~isfinite(value) || value <= 0 || floor(value) ~= value
    error('BuildStratifiedRandomFieldSamplePlan:InvalidInteger', ...
        'cfg.%s must be a positive integer.', field_name);
end
end

function value = getConfigValue(cfg, field_name, default_value)
value = default_value;
if isstruct(cfg) && isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    value = cfg.(field_name);
end
end
