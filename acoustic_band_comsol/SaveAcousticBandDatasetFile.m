function dataset_file = SaveAcousticBandDatasetFile(result, sample, cfg)
%SAVEACOUSTICBANDDATASETFILE Save one compact MAT file for dataset generation.

if nargin < 3 || isempty(cfg)
    cfg = result.config;
end
if nargin < 2
    sample = struct();
end
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

dataset = struct();
dataset.meta = buildMeta(result, sample, cfg);
dataset.geometry = buildGeometry(result);
dataset.kpath = buildKPath(result);
dataset.bands = buildBands(result);
dataset.fields = buildFields(result);
dataset.provenance = buildProvenance(result, sample, cfg);

dataset_file = fullfile(cfg.output_dir, [cfg.case_id, '_band.mat']);
if exist(dataset_file, 'file')
    delete(dataset_file);
end
try
    save(dataset_file, 'dataset', '-v7.3');
catch
    if exist(dataset_file, 'file')
        delete(dataset_file);
    end
    save(dataset_file, 'dataset', '-v7');
end
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
