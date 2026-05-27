function cfg = band_dataset_config_template(varargin)
%BAND_DATASET_CONFIG_TEMPLATE Default config for batch COMSOL band datasets.

bspline_root = AddAcousticBandPaths();
tensor_dir = fullfile(bspline_root, 'tensors', 'tensors');
output_dir = fullfile(bspline_root, 'acoustic_band_comsol', 'dataset_output');

cfg = struct();
cfg.tensor_dir = tensor_dir;
cfg.tensor_files = {};
cfg.output_dir = output_dir;
cfg.worker_count = 2;
cfg.worker_id = [];
cfg.skip_completed = true;
cfg.case_name_suffix = '';
cfg.worker_launch_mode = 'matlab';
cfg.worker_matlab_bin = 'matlab';
cfg.comsol_root = '';
cfg.comsol_mli_dir = '';
cfg.comsol_host = '127.0.0.1';
cfg.comsol_port = 2036;
cfg.comsol_reuse_existing_server = false;
cfg.enable_worker_comsol_recovery = true;
cfg.case_infra_retry_limit = 1;
cfg.worker_infra_failure_limit = 3;
cfg.worker_recovery_backoff_s = 5;
cfg.worker_healthcheck_before_claim = true;

cfg.unit_cell_length = 1.0;
cfg.grid_resolution = 256;
cfg.field_grid_resolution = 256;
cfg.total_k_points = 71;
cfg.num_eigenfrequencies = 8;
cfg.search_frequency = 1000;
cfg.mesh_max_size_fraction = 1 / 35;
cfg.mesh_min_size_fraction = 1 / 300;
cfg.density = 1.21;
cfg.sound_speed = 343;
cfg.solid_phase_value = 1;
cfg.save_model = false;
cfg.write_standard_outputs = false;
cfg.verbose = true;

if nargin == 1 && isstruct(varargin{1})
    cfg = mergeStruct(cfg, varargin{1});
elseif mod(nargin, 2) == 0
    for i = 1:2:nargin
        cfg.(char(varargin{i})) = varargin{i + 1};
    end
elseif nargin ~= 0
    error('band_dataset_config_template:InvalidInput', ...
        'Use a struct or name-value pairs.');
end

end

function out = mergeStruct(out, in)
names = fieldnames(in);
for i = 1:numel(names)
    out.(names{i}) = in.(names{i});
end
end
