function fields = ExtractComsolModeFieldStack(model, cfg, band_frequencies_hz, bz)
%EXTRACTCOMSOLMODEFIELDSTACK Sample all solved mode fields on a regular grid.
%
% The output field tensor is [ny, nx, n_band, n_k], matching image-style
% indexing for downstream dataset generation.

if nargin < 4
    bz = struct();
end

nx = cfg.field_grid_resolution;
ny = cfg.field_grid_resolution;
n_k = size(band_frequencies_hz, 1);
n_band = size(band_frequencies_hz, 2);

x = linspace(0, cfg.unit_cell_length, nx);
y = linspace(0, cfg.unit_cell_length, ny);
[X, Y] = meshgrid(x, y);
coords = [X(:).'; Y(:).'];

fields = struct();
fields.grid_resolution = [ny, nx];
fields.x = x;
fields.y = y;
fields.expression = '';
fields.value_transform = 'real';
fields.data = nan(ny, nx, n_band, n_k);
fields.status = strings(n_k, n_band);
fields.path_name = getOptionalField(bz, 'path_name', '');

expr = resolveFieldExpression(model, cfg, coords);
fields.expression = expr;

soltag_map = inferSolutionTagsByK(model, n_k);

for ik = 1:n_k
    for ib = 1:n_band
        if ~isfinite(band_frequencies_hz(ik, ib))
            fields.status(ik, ib) = "missing_frequency";
            continue;
        end
        try
            values = sampleOneModeField(model, expr, coords, ik, ib, soltag_map);
            values = applyValueTransform(values, fields.value_transform);
            values = values(:);
            if numel(values) ~= nx * ny
                error('Unexpected sampled value count: %d', numel(values));
            end
            fields.data(:, :, ib, ik) = reshape(values, ny, nx);
            fields.status(ik, ib) = "ok";
        catch ME
            fields.status(ik, ib) = "failed: " + string(ME.message);
        end
    end
end

function values = sampleOneModeField(model, expr, coords, ik, ib, soltag_map)
attempts = { ...
    @() mphinterp(model, expr, 'coord', coords, ...
        'dataset', 'dset1', 'outersolnum', ik, 'solnum', ib, ...
        'coorderr', 'off')};

soltag = soltag_map{ik};
if ~isempty(soltag)
    attempts{end + 1} = @() sampleFromSolutionTag(model, soltag, expr, coords, ib); %#ok<AGROW>
end

last_error = [];
last_nan_only = false;
for i = 1:numel(attempts)
    try
        values = attempts{i}();
        if hasFiniteSample(values)
            return;
        end
        last_nan_only = true;
    catch ME
        last_error = ME;
    end
end

if last_nan_only
    error('ExtractComsolModeFieldStack:NaNOnlySample', ...
        'Expression %s evaluated but returned no finite samples.', expr);
end
rethrow(last_error);
end

end

function expr = resolveFieldExpression(model, cfg, coords)
candidates = cfg.field_expression_candidates;
probe_coords = buildProbeCoords(cfg, coords);
fallback_expr = '';
for i = 1:numel(candidates)
    expr = candidates{i};
    try
        values = mphinterp(model, expr, 'coord', probe_coords, ...
            'dataset', 'dset1', 'outersolnum', 1, 'solnum', 1, ...
            'coorderr', 'off');
        if isempty(fallback_expr)
            fallback_expr = expr;
        end
        if hasFiniteSample(values)
            return;
        end
    catch
    end
end

if ~isempty(fallback_expr)
    expr = fallback_expr;
    return;
end

error('ExtractComsolModeFieldStack:NoValidExpression', ...
    'None of the field expression candidates succeeded.');
end

function probe_coords = buildProbeCoords(cfg, coords)
probe_coords = coords(:, 1:min(size(coords, 2), 9));

L = cfg.unit_cell_length;
center = L * [0.5, 0.5];
offsets = L * [ ...
    0.25, 0.25; ...
    0.25, 0.50; ...
    0.25, 0.75; ...
    0.50, 0.25; ...
    0.50, 0.50; ...
    0.50, 0.75; ...
    0.75, 0.25; ...
    0.75, 0.50; ...
    0.75, 0.75];
probe_coords = [center(:), offsets.' ];
end

function values = applyValueTransform(values, transform_name)
switch char(transform_name)
    case 'real'
        values = real(values);
    case 'abs'
        values = abs(values);
    otherwise
        values = real(values);
end
end

function tf = hasFiniteSample(values)
values = values(:);
tf = any(isfinite(real(values)));
end

function soltag_map = inferSolutionTagsByK(model, n_k)
soltag_map = cell(n_k, 1);
try
    sol_tags = cell(model.sol.tags());
catch
    return;
end

for i = 1:numel(sol_tags)
    soltag = sol_tags{i};
    ik = solutionTagParameterIndex(model, soltag, n_k);
    if ~isnan(ik)
        soltag_map{ik} = soltag;
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

function values = sampleFromSolutionTag(model, soltag, expr, coords, solnum)
dtag = ['tmp_field_', char(soltag)];
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

values = mphinterp(model, expr, 'coord', coords, ...
    'dataset', dtag, 'solnum', solnum, 'coorderr', 'off');
end

function removeDatasetIfPresent(model, dtag)
try
    model.result.dataset.remove(dtag);
catch
end
end

function value = getOptionalField(data, field_name, default_value)
if isstruct(data) && isfield(data, field_name)
    value = data.(field_name);
else
    value = default_value;
end
end
