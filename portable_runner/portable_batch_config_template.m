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

% ---------------- COMSOL / LiveLink startup ----------------
% Recommended flow:
%   1. Open COMSOL with MATLAB manually.
%   2. Run portable_run_batch from that session.
%   3. This host session generates worker launch files.
%   4. Each worker starts via plain `matlab -batch` and launches its own
%      isolated COMSOL server inside run_band_dataset_worker.
cfg.worker_launch_mode = 'matlab';
cfg.worker_matlab_bin = 'matlab';
cfg.comsol_root = 'D:\Software\COMSOL\COMSOL63\Multiphysics';
cfg.comsol_mli_dir = fullfile(cfg.comsol_root, 'mli');
cfg.comsol_host = '127.0.0.1';
cfg.comsol_port = 2036;
cfg.comsol_reuse_existing_server = false;
cfg.enable_worker_comsol_recovery = true;
cfg.case_infra_retry_limit = 1;
cfg.worker_infra_failure_limit = 3;
cfg.worker_recovery_backoff_s = 5;
cfg.worker_healthcheck_before_claim = true;
cfg.worker_restart_comsol_every_n_cases = 10;
cfg.comsol_server_start_retry_limit = 4;
cfg.comsol_server_start_retry_backoff_s = 3;
cfg.comsol_server_start_lock_timeout_s = 300;

% ---------------- Core simulation parameters ----------------
cfg.unit_cell_length = 1.0;
cfg.grid_resolution = 256;
cfg.field_grid_resolution = 256;
cfg.total_k_points = 51;
cfg.num_eigenfrequencies = 10;
cfg.search_frequency = 0;
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
%
% Advanced option:
% If you deliberately want all workers to attach to an existing shared
% COMSOL server, set:
% cfg.comsol_reuse_existing_server = true;
% cfg.comsol_host = '127.0.0.1';
% cfg.comsol_port = 2036;
end
