function dataset_files = SaveAcousticBandDatasetFile(result, sample, cfg)
%SAVEACOUSTICBANDDATASETFILE Save band data and optional sampled field data.

if nargin < 3 || isempty(cfg)
    cfg = result.config;
end
if nargin < 2
    sample = struct();
end
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

split_files = resolveLogicalConfig(cfg, 'split_band_and_fields_files', true);
dataset = buildBandDataset(result, sample, cfg, ~split_files);

band_dataset_file = fullfile(cfg.output_dir, [cfg.case_id, '_band.mat']);
saveStructToMatFile(band_dataset_file, 'dataset', dataset);

fields_dataset_file = fullfile(cfg.output_dir, [cfg.case_id, '_fields.mat']);
if split_files && ~isempty(result.band_frequencies_hz) && shouldSaveSampledFieldsFile(cfg)
    fields_dataset = buildSampledFieldsDataset(result, cfg);
    saveStructToMatFile(fields_dataset_file, 'fields_dataset', fields_dataset);
else
    deleteIfPresent(fields_dataset_file);
end

dataset_files = struct( ...
    'band_dataset_file', band_dataset_file, ...
    'fields_dataset_file', fields_dataset_fileIfPresent(fields_dataset_file));
end

function dataset = buildBandDataset(result, sample, cfg, include_fields)
dataset = struct();
dataset.meta = buildMeta(result, sample, cfg);
dataset.geometry = buildGeometry(result);
dataset.kpath = buildKPath(result);
dataset.bands = buildBands(result);
if include_fields
    dataset.fields = buildFields(result);
end
dataset.provenance = buildProvenance(result, sample, cfg);
end

function meta = buildMeta(result, sample, cfg)
meta = struct();
meta.case_id = result.case_id;
meta.source_mat_file = getOptionalField(sample, 'tensor_file', '');
meta.symmetry_group = result.geometry.symmetry_group;
meta.unit_cell_length = cfg.unit_cell_length;
meta.grid_resolution = cfg.grid_resolution;
meta.total_k_points = size(result.brillouin_zone.k_points, 1);
meta.num_eigenfrequencies_requested = cfg.num_eigenfrequencies;
meta.solid_phase_value = cfg.solid_phase_value;
meta.density = cfg.density;
meta.sound_speed = cfg.sound_speed;
meta.search_frequency = cfg.search_frequency;
meta.field_grid_resolution = cfg.field_grid_resolution;
meta.generated_at = char(datetime('now', 'TimeZone', 'local', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
meta.hostname = getHostName();
end

function geometry = buildGeometry(result)
geometry = struct();
geometry.xPhys_raw = result.geometry.xPhysRaw;
geometry.xPhys_canonical = result.geometry.xPhysCanonical;
geometry.solid_mask_canonical = result.geometry.solidMaskCanonical;
geometry.solid_mask_display = result.geometry.solidMaskDisplay;
geometry.void_mask_for_comsol = result.geometry.voidMaskForComsol;
geometry.display_image = result.geometry.displayImage;
geometry.solid_volume_fraction = getOptionalField(result.geometry, ...
    'solid_volume_fraction', NaN);
geometry.projected_volume_fraction = getOptionalField(result.geometry, ...
    'volume_fraction', NaN);
end

function kpath = buildKPath(result)
bz = result.brillouin_zone;
kpath = struct();
kpath.labels = bz.high_symmetry_labels;
kpath.high_symmetry_points = bz.high_symmetry_points;
kpath.k_points = bz.k_points;
kpath.path_coordinate = bz.path_coordinate;
kpath.tick_coordinate = bz.tick_coordinate;
kpath.point_labels = bz.point_labels;
kpath.path_name = bz.path_name;
end

function bands = buildBands(result)
bands = struct();
bands.frequencies_hz = result.band_frequencies_hz;
bands.status_by_k = getOptionalField(result.comsol, 'status', strings(0, 1));
end

function fields_dataset = buildSampledFieldsDataset(result, cfg)
mode_fields = getOptionalField(result.comsol, 'mode_fields', struct());
n_k = size(result.band_frequencies_hz, 1);
n_band = size(result.band_frequencies_hz, 2);
sample_plan = BuildStratifiedRandomFieldSamplePlan(n_k, n_band, cfg);
target_resolution = resolvePositiveIntegerConfig(cfg, ...
    'field_output_grid_resolution', 128);
output_dtype = char(string(getOptionalField(cfg, 'field_output_dtype', 'single')));

field_data = initializeFieldData(target_resolution, sample_plan.sample_count, output_dtype);
field_status = normalizeFieldStatusMatrix(mode_fields, n_k, n_band);
sampled_status = strings(sample_plan.sample_count, 1);
sampled_frequency_hz = nan(sample_plan.sample_count, 1);
sampled_path_coordinate = nan(sample_plan.sample_count, 1);
sampled_k_points = nan(sample_plan.sample_count, 2);

raw_field_data = getOptionalField(mode_fields, 'data', []);
has_field_data = hasSampleableFieldData(raw_field_data, n_k, n_band);

for i = 1:sample_plan.sample_count
    ik = sample_plan.selection_ik(i);
    ib = sample_plan.selection_ib(i);
    sampled_status(i) = field_status(ik, ib);
    sampled_frequency_hz(i) = result.band_frequencies_hz(ik, ib);
    sampled_path_coordinate(i) = result.brillouin_zone.path_coordinate(ik);
    sampled_k_points(i, :) = result.brillouin_zone.k_points(ik, :);
    if has_field_data
        resized = resizeFieldSlice(raw_field_data(:, :, ib, ik), target_resolution);
        field_data(:, :, i) = castFieldSlice(resized, output_dtype);
    end
end

fields_dataset = struct();
fields_dataset.case_id = result.case_id;
fields_dataset.selection_ik = sample_plan.selection_ik;
fields_dataset.selection_ib = sample_plan.selection_ib;
fields_dataset.selection_linear_index = sample_plan.selection_linear_index;
fields_dataset.block_k_index = sample_plan.block_k_index;
fields_dataset.block_band_index = sample_plan.block_band_index;
fields_dataset.path_coordinate = sampled_path_coordinate;
fields_dataset.k_points = sampled_k_points;
fields_dataset.band_frequencies_hz = sampled_frequency_hz;
fields_dataset.field_data = field_data;
fields_dataset.field_status = sampled_status;
fields_dataset.field_expression = string(getOptionalField(mode_fields, 'expression', ''));
fields_dataset.field_grid_resolution_original = getOptionalField(mode_fields, ...
    'grid_resolution', []);
fields_dataset.field_grid_resolution_saved = [target_resolution, target_resolution];
fields_dataset.field_output_dtype = output_dtype;
fields_dataset.sampling_metadata = struct( ...
    'sampling_mode', char(string(getOptionalField(cfg, ...
        'field_sampling_mode', 'stratified_random'))), ...
    'field_sample_count', sample_plan.sample_count, ...
    'field_sample_k_bins', sample_plan.k_bins, ...
    'field_sample_band_bins', sample_plan.band_bins, ...
    'task_sequence_index', getOptionalField(cfg, 'task_sequence_index', []), ...
    'save_fields_for_sample_stride', getOptionalField(cfg, ...
        'save_fields_for_sample_stride', 10), ...
    'save_fields_for_sample_offset', getOptionalField(cfg, ...
        'save_fields_for_sample_offset', 1));
end

function fields = buildFields(result)
fields = struct();
fields.pressure_real_256 = [];
fields.expression = '';
fields.status = strings(0, 0);
fields.grid_resolution = [];
fields.x = [];
fields.y = [];

if isfield(result, 'comsol') && isstruct(result.comsol) && ...
        isfield(result.comsol, 'mode_fields') && isstruct(result.comsol.mode_fields)
    mode_fields = result.comsol.mode_fields;
    fields.pressure_real_256 = getOptionalField(mode_fields, 'data', []);
    fields.expression = getOptionalField(mode_fields, 'expression', '');
    fields.status = getOptionalField(mode_fields, 'status', strings(0, 0));
    fields.grid_resolution = getOptionalField(mode_fields, 'grid_resolution', []);
    fields.x = getOptionalField(mode_fields, 'x', []);
    fields.y = getOptionalField(mode_fields, 'y', []);
end
end

function provenance = buildProvenance(result, sample, cfg)
provenance = struct();
provenance.config = cfg;
provenance.periodic_pairs = getOptionalField(result.comsol, 'periodic_pairs', struct());
provenance.periodic_x = getOptionalField(result.comsol, 'periodic_x', false);
provenance.periodic_y = getOptionalField(result.comsol, 'periodic_y', false);
provenance.extraction = getOptionalField(result.comsol, 'extraction', struct());
provenance.sample_fields = fieldnames(sample);
if isfield(result, 'geometry_validation')
    provenance.geometry_validation = result.geometry_validation;
end
end

function tf = shouldSaveSampledFieldsFile(cfg)
stride = resolvePositiveIntegerConfig(cfg, 'save_fields_for_sample_stride', 10);
offset = resolvePositiveIntegerConfig(cfg, 'save_fields_for_sample_offset', 1);
task_sequence_index = getOptionalField(cfg, 'task_sequence_index', []);
if isempty(task_sequence_index)
    tf = true;
    return;
end
task_sequence_index = double(task_sequence_index);
if ~isscalar(task_sequence_index) || ~isfinite(task_sequence_index) || ...
        floor(task_sequence_index) ~= task_sequence_index || task_sequence_index <= 0
    error('SaveAcousticBandDatasetFile:InvalidTaskSequenceIndex', ...
        'cfg.task_sequence_index must be a positive integer when provided.');
end
tf = mod(task_sequence_index - offset, stride) == 0;
end

function data = initializeFieldData(target_resolution, sample_count, output_dtype)
switch lower(output_dtype)
    case {'single', 'float', 'float32'}
        data = nan(target_resolution, target_resolution, sample_count, 'single');
    case {'double', 'float64'}
        data = nan(target_resolution, target_resolution, sample_count);
    otherwise
        error('SaveAcousticBandDatasetFile:UnsupportedFieldOutputDType', ...
            'Unsupported cfg.field_output_dtype: %s', output_dtype);
end
end

function tf = hasSampleableFieldData(raw_field_data, n_k, n_band)
tf = ~isempty(raw_field_data) && ndims(raw_field_data) == 4 && ...
    size(raw_field_data, 3) >= n_band && size(raw_field_data, 4) >= n_k;
end

function resized = resizeFieldSlice(field_slice, target_resolution)
field_slice = double(field_slice);
[ny, nx] = size(field_slice);
if ny == target_resolution && nx == target_resolution
    resized = field_slice;
    return;
end
[xq, yq] = meshgrid(linspace(1, nx, target_resolution), ...
    linspace(1, ny, target_resolution));
resized = interp2(field_slice, xq, yq, 'linear');
end

function cast_slice = castFieldSlice(field_slice, output_dtype)
switch lower(output_dtype)
    case {'single', 'float', 'float32'}
        cast_slice = single(field_slice);
    case {'double', 'float64'}
        cast_slice = double(field_slice);
    otherwise
        error('SaveAcousticBandDatasetFile:UnsupportedFieldOutputDType', ...
            'Unsupported cfg.field_output_dtype: %s', output_dtype);
end
end

function status_matrix = normalizeFieldStatusMatrix(mode_fields, n_k, n_band)
status_value = getOptionalField(mode_fields, 'status', strings(0, 0));
if isempty(status_value)
    status_matrix = strings(n_k, n_band);
    return;
end

status_value = string(status_value);
if isscalar(status_value)
    status_matrix = repmat(status_value, n_k, n_band);
    return;
end
if isequal(size(status_value), [n_k, n_band])
    status_matrix = status_value;
    return;
end

status_matrix = repmat("", n_k, n_band);
copy_rows = min(size(status_value, 1), n_k);
copy_cols = min(size(status_value, 2), n_band);
status_matrix(1:copy_rows, 1:copy_cols) = status_value(1:copy_rows, 1:copy_cols);
end

function saveStructToMatFile(filename, variable_name, value)
deleteIfPresent(filename);
switch variable_name
    case 'dataset'
        dataset = value; %#ok<NASGU>
        try
            save(filename, 'dataset', '-v7.3');
        catch
            deleteIfPresent(filename);
            save(filename, 'dataset', '-v7');
        end
    case 'fields_dataset'
        fields_dataset = value; %#ok<NASGU>
        try
            save(filename, 'fields_dataset', '-v7.3');
        catch
            deleteIfPresent(filename);
            save(filename, 'fields_dataset', '-v7');
        end
    otherwise
        error('SaveAcousticBandDatasetFile:UnsupportedVariableName', ...
            'Unsupported MAT variable name: %s', variable_name);
end
end

function deleteIfPresent(filename)
if exist(filename, 'file')
    delete(filename);
end
end

function text = fields_dataset_fileIfPresent(filename)
if exist(filename, 'file')
    text = filename;
else
    text = '';
end
end

function value = resolveLogicalConfig(cfg, field_name, default_value)
value = getOptionalField(cfg, field_name, default_value);
if islogical(value)
    return;
end
if isnumeric(value)
    value = value ~= 0;
    return;
end
value = strcmpi(char(string(value)), 'true');
end

function value = resolvePositiveIntegerConfig(cfg, field_name, default_value)
value = double(getOptionalField(cfg, field_name, default_value));
if ~isscalar(value) || ~isfinite(value) || value <= 0 || floor(value) ~= value
    error('SaveAcousticBandDatasetFile:InvalidPositiveIntegerConfig', ...
        'cfg.%s must be a positive integer.', field_name);
end
end

function value = getOptionalField(data, field_name, default_value)
if isstruct(data) && isfield(data, field_name)
    value = data.(field_name);
else
    value = default_value;
end
end

function name = getHostName()
name = '';
try
    name = char(java.net.InetAddress.getLocalHost.getHostName);
catch
end
end
