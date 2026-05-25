function summary = run_band_dataset_worker(config_or_file)
%RUN_BAND_DATASET_WORKER Process one shared batch queue as a single worker.

cfg = normalizeConfig(config_or_file);
AddAcousticBandPaths();

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

task_files = listTensorFiles(cfg);
worker_id = resolveWorkerId(cfg);

summary = struct();
summary.worker_id = worker_id;
summary.output_dir = cfg.output_dir;
summary.records = repmat(struct( ...
    'case_id', '', ...
    'tensor_file', '', ...
    'status', '', ...
    'elapsed_s', NaN, ...
    'dataset_file', '', ...
    'message', ''), 0, 1);

for i = 1:numel(task_files)
    tensor_file = task_files{i};
    [claimed, lock_file, case_id] = tryClaimCase(tensor_file, cfg, worker_id);
    if ~claimed
        continue;
    end

    record = struct( ...
        'case_id', case_id, ...
        'tensor_file', tensor_file, ...
        'status', 'started', ...
        'elapsed_s', NaN, ...
        'dataset_file', '', ...
        'message', '');
    t_start = tic;

    try
        result = runOneTensorCase(tensor_file, cfg, case_id);
        record.status = 'ok';
        record.elapsed_s = toc(t_start);
        record.dataset_file = result.dataset_file;
        finalizeLock(lock_file, 'ok');
    catch ME
        record.status = 'error';
        record.elapsed_s = toc(t_start);
        record.message = ME.message;
        finalizeLock(lock_file, ['error: ', ME.message]);
    end

    summary.records(end + 1, 1) = record; %#ok<AGROW>
    if cfg.verbose
        fprintf('[worker %d] %s | %s | %.2f s\n', ...
            worker_id, case_id, record.status, record.elapsed_s);
    end
end

summary.completed = numel(summary.records);
summary.ok_count = sum(strcmp({summary.records.status}, 'ok'));
summary.error_count = sum(strcmp({summary.records.status}, 'error'));
end

function cfg = normalizeConfig(config_or_file)
if nargin < 1 || isempty(config_or_file)
    cfg = band_dataset_config_template();
elseif isstruct(config_or_file)
    cfg = band_dataset_config_template(config_or_file);
elseif ischar(config_or_file) || isstring(config_or_file)
    loaded = load(char(config_or_file));
    if isfield(loaded, 'cfg')
        cfg = band_dataset_config_template(loaded.cfg);
    else
        error('run_band_dataset_worker:MissingCfg', ...
            'Config MAT file must contain variable cfg.');
    end
else
    error('run_band_dataset_worker:InvalidConfig', ...
        'Unsupported config input.');
end
end

function result = runOneTensorCase(tensor_file, cfg, case_id)
symmetry_group = InferBsplineSymmetryGroup(case_id);

case_output_dir = fullfile(cfg.output_dir, case_id);
if ~exist(case_output_dir, 'dir')
    mkdir(case_output_dir);
end

band_cfg = AcousticBandConfig( ...
    'run_comsol', true, ...
    'save_model', cfg.save_model, ...
    'write_standard_outputs', cfg.write_standard_outputs, ...
    'output_dir', case_output_dir, ...
    'case_id', case_id, ...
    'unit_cell_length', cfg.unit_cell_length, ...
    'grid_resolution', cfg.grid_resolution, ...
    'field_grid_resolution', cfg.field_grid_resolution, ...
    'total_k_points', cfg.total_k_points, ...
    'num_eigenfrequencies', cfg.num_eigenfrequencies, ...
    'search_frequency', cfg.search_frequency, ...
    'mesh_max_size_fraction', cfg.mesh_max_size_fraction, ...
    'mesh_min_size_fraction', cfg.mesh_min_size_fraction, ...
    'density', cfg.density, ...
    'sound_speed', cfg.sound_speed, ...
    'solid_phase_value', cfg.solid_phase_value, ...
    'verbose', cfg.verbose);

result = RunAcousticBandFromTensor(tensor_file, symmetry_group, ...
    cfg.unit_cell_length, band_cfg);
end

function files = listTensorFiles(cfg)
if ~isempty(cfg.tensor_files)
    files = cfg.tensor_files;
    return;
end
listing = dir(fullfile(cfg.tensor_dir, '*_tensor.mat'));
[~, order] = sort({listing.name});
listing = listing(order);
files = cellfun(@(f, n) fullfile(f, n), {listing.folder}, {listing.name}, ...
    'UniformOutput', false);
end

function worker_id = resolveWorkerId(cfg)
if ~isempty(cfg.worker_id)
    worker_id = cfg.worker_id;
else
    worker_id = feature('getpid');
end
end

function [claimed, lock_file, case_id] = tryClaimCase(tensor_file, cfg, worker_id)
[~, base] = fileparts(tensor_file);
case_id = regexprep(base, '_tensor$', '');
if ~isempty(cfg.case_name_suffix)
    case_id = [case_id, cfg.case_name_suffix];
end

case_output_dir = fullfile(cfg.output_dir, case_id);
if ~exist(case_output_dir, 'dir')
    mkdir(case_output_dir);
end

dataset_file = fullfile(case_output_dir, [case_id, '_band.mat']);
done_file = fullfile(case_output_dir, '.done');
lock_file = fullfile(case_output_dir, '.lock');

if cfg.skip_completed && exist(dataset_file, 'file') && exist(done_file, 'file')
    claimed = false;
    return;
end

[fid, msg] = fopen(lock_file, 'x');
if fid < 0
    if contains(msg, 'File exists')
        claimed = false;
        return;
    end
    error('run_band_dataset_worker:LockOpenFailed', ...
        'Cannot create lock file %s: %s', lock_file, msg);
end
fprintf(fid, 'worker=%d\nsource=%s\n', worker_id, tensor_file);
claimed = true;
fclose(fid);
end

function finalizeLock(lock_file, status_text)
[case_output_dir, ~, ~] = fileparts(lock_file);
done_file = fullfile(case_output_dir, '.done');
fid = fopen(done_file, 'w');
if fid >= 0
    fprintf(fid, '%s\n', status_text);
    fclose(fid);
end
if exist(lock_file, 'file')
    delete(lock_file);
end
end
