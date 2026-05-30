function result = RunAcousticBandFromCoefficients(coefficients, symmetry_group, unit_cell_length, varargin)
%RUNACOUSTICBANDFROMCOEFFICIENTS Full acoustic band pipeline from C and group.

cfg = AcousticBandConfig(varargin{:});
cfg.unit_cell_length = unit_cell_length;

if isempty(cfg.case_id)
    cfg.case_id = sprintf('%s_L%.6g', char(symmetry_group), unit_cell_length);
end

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

geom = ReconstructBsplineField(coefficients, symmetry_group, cfg);
boundaries = ExtractBoundaryPolygons(geom, cfg);
bz = resolveBrillouinZonePath(symmetry_group, unit_cell_length, cfg);

result = struct();
result.case_id = cfg.case_id;
result.config = cfg;
result.geometry = geom;
result.boundaries = boundaries;
result.brillouin_zone = bz;
result.comsol = [];
result.output_files = struct();

if cfg.run_comsol
    result.comsol = RunComsolAcousticBands(geom, bz, cfg);
    result.band_frequencies_hz = result.comsol.band_frequencies_hz;
else
    result.band_frequencies_hz = [];
end

result.dataset_files = SaveAcousticBandDatasetFile(result, struct(), cfg);
result.dataset_file = result.dataset_files.band_dataset_file;
if cfg.write_standard_outputs
    result.output_files = SaveAcousticBandResult(result, cfg);
else
    result.output_files = struct( ...
        'dataset_mat', result.dataset_file, ...
        'fields_dataset_mat', result.dataset_files.fields_dataset_file);
end
result.output_files.dataset_mat = result.dataset_file;
result.output_files.fields_dataset_mat = result.dataset_files.fields_dataset_file;

end

function bz = resolveBrillouinZonePath(symmetry_group, unit_cell_length, cfg)
if isfield(cfg, 'total_k_points') && ~isempty(cfg.total_k_points)
    bz = BuildFixedKPathFromSymmetry(symmetry_group, unit_cell_length, ...
        cfg.total_k_points, cfg);
else
    bz = GetBrillouinZonePath(symmetry_group, unit_cell_length, cfg);
end
end
