function cfg = portable_batch_config_template()
%PORTABLE_BATCH_CONFIG_TEMPLATE Editable config for portable COMSOL batch runs.
%
% Edit this file on the target machine before running.

paths = portable_add_paths();

cfg = band_dataset_config_template();

% ---------------- Required paths ----------------
cfg.tensor_dir = 'D:\Desktop\portable_batch_package_dist\dist\dataset\tensors';
cfg.tensor_files = {};
cfg.output_dir = fullfile(paths.package_root, 'output');

% ---------------- Batch parallelism ----------------
cfg.worker_count = 2;
cfg.worker_id = [];
cfg.skip_completed = true;
cfg.case_name_suffix = '';

% ---------------- Core simulation parameters ----------------
cfg.unit_cell_length = 1.0;
cfg.grid_resolution = 256;
cfg.field_grid_resolution = 256;
cfg.total_k_points = 51;
cfg.num_eigenfrequencies = 10;
cfg.search_frequency = 1000;
cfg.mesh_max_size_fraction = 1 / 35;
cfg.mesh_min_size_fraction = 1 / 300;

% ---------------- Material / phase definition ----------------
cfg.density = 1.21;
cfg.sound_speed = 343;
cfg.solid_phase_value = 0;
% solid_phase_value = 1:
%   tensor/mat image black region (mat==1) is treated as solid
% solid_phase_value = 0:
%   tensor/mat image white region (mat==0) is treated as solid

% ---------------- Output controls ----------------
cfg.save_model = true;
cfg.write_standard_outputs = true;
cfg.verbose = true;

% ---------------- Optional: run only a selected subset ----------------
% Example 1:
% cfg.tensor_files = { ...
%     'D:\dataset\p4_Vol0.53_K0.0000_Sample_103461_tensor.mat', ...
%     'D:\dataset\p4mm_Vol0.31_K0.0000_Sample_100987_tensor.mat'};
%
% Example 2:
% cfg.tensor_files = {};
% cfg.tensor_dir = 'D:\dataset\subset_100';
end
