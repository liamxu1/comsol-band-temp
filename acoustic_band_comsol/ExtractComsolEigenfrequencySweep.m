function [freqs, status, extraction] = ExtractComsolEigenfrequencySweep(model, n_bands, n_k)
%EXTRACTCOMSOLEIGENFREQUENCYSWEEP Read all bands from an internal ik sweep.

if nargin < 2 || isempty(n_bands)
    n_bands = inf;
end
if nargin < 3 || isempty(n_k)
    n_k = inferOuterSolutionCount(model);
end
if ~isfinite(n_bands)
    error('ExtractComsolEigenfrequencySweep:FiniteBandCountRequired', ...
        'A finite band count is required to assemble a rectangular matrix.');
end

freqs = nan(n_k, n_bands);
status = strings(n_k, 1);
raw = cell(n_k, 1);

for ik = 1:n_k
    try
        f = extractOneOuterSolution(model, ik);
        raw{ik} = f(:);
        if numel(f) > n_bands
            f = f(1:n_bands);
        end
        freqs(ik, 1:numel(f)) = f(:).';
        status(ik) = "ok";
    catch ME
        status(ik) = "failed: " + string(ME.message);
    end
end

if nnz(any(isfinite(freqs), 2)) < n_k
    [fallback, raw_by_soltag] = extractSolutionTagSweepFallback(model, n_bands, n_k);
    if nnz(any(isfinite(fallback), 2)) == n_k
        replace_rows = true(n_k, 1);
    else
        replace_rows = ~any(isfinite(freqs), 2) & any(isfinite(fallback), 2);
    end
    freqs(replace_rows, :) = fallback(replace_rows, :);
    for ik = find(replace_rows).'
        status(ik) = "ok";
        raw{ik} = raw_by_soltag{ik};
    end
end

if ~any(isfinite(freqs(:)))
    fallback = extractWholeSweepFallback(model, n_bands, n_k);
    if any(isfinite(fallback(:)))
        freqs = fallback;
        status(:) = "ok";
    end
end

for ik = find(~any(isfinite(freqs), 2)).'
    warning('ExtractComsolEigenfrequencySweep:KPointFailed', ...
        'Could not extract eigenfrequencies for ik=%d: %s', ik, status(ik));
end

extraction = struct();
extraction.n_kpoints = n_k;
extraction.num_bands_requested = n_bands;
extraction.num_finite = nnz(isfinite(freqs));
extraction.raw_by_ik = raw;
extraction.solinfo = [];
try
    extraction.solinfo = mphsolinfo(model);
catch
end

function [freqs, raw] = extractSolutionTagSweepFallback(model, n_bands, n_k)
freqs = nan(n_k, n_bands);
raw = cell(n_k, 1);
try
    sol_tags = cell(model.sol.tags());
catch
    return;
end

for i = 1:numel(sol_tags)
    soltag = sol_tags{i};
    ik = solutionTagParameterIndex(model, soltag, n_k);
    if isnan(ik)
        continue;
    end
    try
        f = extractFrequenciesFromSolutionTag(model, soltag);
        raw{ik} = f(:);
        if numel(f) > n_bands
            f = f(1:n_bands);
        end
        freqs(ik, 1:numel(f)) = f(:).';
    catch
    end
end
end

function ik = solutionTagParameterIndex(model, soltag, n_k)
ik = nan;
try
    info = mphsolinfo(model, 'soltag', soltag);
    if isfield(info, 'paramsweepvals') && numel(info.paramsweepvals) == 1
        candidate = round(real(info.paramsweepvals));
        if isfinite(candidate) && candidate >= 1 && candidate <= n_k
            ik = candidate;
        end
    end
catch
end
end

function f = extractFrequenciesFromSolutionTag(model, soltag)
dtag = ['tmp_', char(soltag)];
try
    model.result.dataset.remove(dtag);
catch
end
ds = model.result.dataset.create(dtag, 'Solution');
cleanup = onCleanup(@() removeDatasetIfPresent(model, dtag));
try
    ds.set('solution', soltag);
catch
    ds.set('soltag', soltag);
end

vars = {'freq', 'acpr.freq'};
f = [];
for i = 1:numel(vars)
    attempts = {@() mphglobal(model, vars{i}, 'dataset', dtag, 'solnum', 'all')};
    f = firstFiniteFrequency(attempts, false);
    if ~isempty(f)
        return;
    end
end

attempts = {@() mphglobal(model, 'lambda', 'dataset', dtag, 'solnum', 'all')};
f = firstFiniteFrequency(attempts, true);
if isempty(f)
    error('ExtractComsolEigenfrequencySweep:NoSolTagFrequencies', ...
        'No frequencies found for solution tag %s.', soltag);
end
end

function removeDatasetIfPresent(model, dtag)
try
    model.result.dataset.remove(dtag);
catch
end
end

function freqs = extractWholeSweepFallback(model, n_bands, n_k)
freqs = nan(n_k, n_bands);
vars = {'freq', 'acpr.freq'};
for i = 1:numel(vars)
    attempts = {@() mphglobal(model, vars{i}, 'dataset', 'dset1', 'solnum', 'all'), ...
                @() mphglobal(model, vars{i}, 'solnum', 'all')};
    val = firstRawVector(attempts, false);
    if ~isempty(val)
        freqs = reshapeSweepVector(val, n_bands, n_k);
        if any(isfinite(freqs(:)))
            return;
        end
    end
end

attempts = {@() mphglobal(model, 'lambda', 'dataset', 'dset1', 'solnum', 'all'), ...
            @() mphglobal(model, 'lambda', 'solnum', 'all')};
val = firstRawVector(attempts, true);
if ~isempty(val)
    freqs = reshapeSweepVector(val, n_bands, n_k);
end
end

function val = firstRawVector(attempts, convert_lambda)
val = [];
for i = 1:numel(attempts)
    try
        candidate = attempts{i}();
        candidate = candidate(:);
        if convert_lambda
            candidate = sqrt(abs(candidate)) / (2 * pi);
        end
        candidate = real(candidate);
        candidate(~isfinite(candidate) | candidate < 0) = nan;
        if any(isfinite(candidate))
            val = candidate;
            return;
        end
    catch
    end
end
end

function freqs = reshapeSweepVector(val, n_bands, n_k)
freqs = nan(n_k, n_bands);
if numel(val) < n_k
    return;
end

if numel(val) >= n_k * n_bands
    val = val(1:(n_k * n_bands));
    mat = reshape(val, n_bands, n_k).';
else
    bands_per_k = floor(numel(val) / n_k);
    if bands_per_k < 1
        return;
    end
    val = val(1:(n_k * bands_per_k));
    mat = reshape(val, bands_per_k, n_k).';
end

for i = 1:size(mat, 1)
    row = sort(mat(i, isfinite(mat(i, :))));
    freqs(i, 1:min(numel(row), n_bands)) = row(1:min(numel(row), n_bands));
end
end

end

function f = extractOneOuterSolution(model, ik)
vars = {'freq', 'acpr.freq'};
f = [];
for i = 1:numel(vars)
    attempts = {@() mphglobal(model, vars{i}, 'dataset', 'dset1', ...
                    'outersolnum', ik, 'solnum', 'all'), ...
                @() mphglobal(model, vars{i}, ...
                    'outersolnum', ik, 'solnum', 'all')};
    f = firstFiniteFrequency(attempts, false);
    if ~isempty(f)
        return;
    end
end

attempts = {@() mphglobal(model, 'lambda', 'dataset', 'dset1', ...
                'outersolnum', ik, 'solnum', 'all'), ...
            @() mphglobal(model, 'lambda', ...
                'outersolnum', ik, 'solnum', 'all')};
f = firstFiniteFrequency(attempts, true);
if ~isempty(f)
    return;
end

error('ExtractComsolEigenfrequencySweep:NoFrequencies', ...
    'No finite eigenfrequencies were found for outer solution ik=%d.', ik);
end

function f = firstFiniteFrequency(attempts, convert_lambda)
f = [];
for i = 1:numel(attempts)
    try
        val = attempts{i}();
        val = val(:);
        if convert_lambda
            val = sqrt(abs(val)) / (2 * pi);
        end
        val = real(val);
        val = val(isfinite(val) & val >= 0);
        if ~isempty(val)
            f = sort(val);
            return;
        end
    catch
    end
end
end

function n_k = inferOuterSolutionCount(model)
n_k = 1;
try
    info = mphsolinfo(model);
    if isfield(info, 'paramsweepvals') && ~isempty(info.paramsweepvals)
        n_k = numel(info.paramsweepvals);
    elseif isfield(info, 'batch') && isfield(info.batch, 'pvals') && ~isempty(info.batch.pvals)
        n_k = numel(info.batch.pvals);
    end
catch
end
end
