function launch = portable_run_batch()
%PORTABLE_RUN_BATCH Entry point for portable COMSOL batch generation.

portable_add_paths();
cfg = portable_batch_config_template();

if ~exist(cfg.tensor_dir, 'dir') && isempty(cfg.tensor_files)
    error('portable_run_batch:MissingTensorDir', ...
        'tensor_dir does not exist: %s', cfg.tensor_dir);
end

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

fprintf('Portable batch run configuration:\n');
fprintf('  tensor_dir: %s\n', cfg.tensor_dir);
fprintf('  output_dir: %s\n', cfg.output_dir);
fprintf('  worker_count: %d\n', cfg.worker_count);
fprintf('  grid_resolution: %d\n', cfg.grid_resolution);
fprintf('  field_grid_resolution: %d\n', cfg.field_grid_resolution);
fprintf('  total_k_points: %d\n', cfg.total_k_points);
fprintf('  num_eigenfrequencies: %d\n', cfg.num_eigenfrequencies);
fprintf('  solid_phase_value: %d\n', cfg.solid_phase_value);

launch = run_band_dataset_batch(cfg);

disp('Worker launch commands:');
disp(launch.commands);
disp('Worker logs:');
disp(launch.log_files);
end
