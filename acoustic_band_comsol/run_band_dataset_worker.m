function summary = run_band_dataset_worker(config_or_file)
%RUN_BAND_DATASET_WORKER Process one shared batch queue as a single worker.

cfg = normalizeConfig(config_or_file);
AddAcousticBandPaths();
initializeWorkerComsol(cfg);

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

function initializeWorkerComsol(cfg)
if cfg.verbose
    fprintf('[worker-init] mode=manual COMSOL-with-MATLAB host + per-worker isolated server\n');
end

loadComsolMli(cfg);

if hasLiveLinkConnection()
    if cfg.verbose
        fprintf('[worker-init] Existing COMSOL LiveLink session detected; reusing current connection\n');
        fprintf('[worker-init] LIVELINK_INIT_OK\n');
    end
    return;
end

if ~hasCallableSymbol('mphstart')
    errorWithCode('MPHSTART_UNAVAILABLE', ...
        ['COMSOL LiveLink function mphstart is not available after adding ', ...
        'cfg.comsol_mli_dir: %s'], cfg.comsol_mli_dir);
end

if cfg.comsol_reuse_existing_server
    connectSharedServer(cfg);
else
    startIsolatedServer(cfg);
end

ensureModelUtilAvailable();

if cfg.verbose
    fprintf('[worker-init] LIVELINK_INIT_OK\n');
end
end

function loadComsolMli(cfg)
if ~isfield(cfg, 'comsol_mli_dir') || isempty(cfg.comsol_mli_dir)
    errorWithCode('MLI_NOT_CONFIGURED', ...
        'cfg.comsol_mli_dir is empty. Set it to the COMSOL LiveLink mli directory.');
end
if exist(cfg.comsol_mli_dir, 'dir') ~= 7
    errorWithCode('MLI_DIR_MISSING', ...
        'cfg.comsol_mli_dir does not exist: %s', cfg.comsol_mli_dir);
end
addpath(cfg.comsol_mli_dir);
if cfg.verbose
    fprintf('[worker-init] Added COMSOL mli path: %s\n', cfg.comsol_mli_dir);
    fprintf('[worker-init] which mphstart => %s\n', strtrim(which('mphstart')));
    fprintf('[worker-init] which mphstartcomsolmphserver => %s\n', ...
        strtrim(which('mphstartcomsolmphserver')));
end
end

function connectSharedServer(cfg)
host = resolveConfigString(cfg, 'comsol_host', '127.0.0.1');
port = resolveConfigNumeric(cfg, 'comsol_port', 2036);
comsol_root = resolveComsolRoot(cfg);

if cfg.verbose
    fprintf('[worker-init] Reusing COMSOL server at %s:%d\n', host, port);
end

try
    mphstart(host, port, comsol_root);
catch ME
    errorWithCode('SERVER_CONNECT_FAILED', ...
        'Failed to connect to COMSOL server at %s:%d: %s', host, port, ME.message);
end
end

function startIsolatedServer(cfg)
comsol_root = resolveComsolRoot(cfg);
host = resolveConfigString(cfg, 'comsol_host', '127.0.0.1');

if ~hasCallableSymbol('mphstartcomsolmphserver')
    errorWithCode('SERVER_HELPER_MISSING', ...
        ['COMSOL helper mphstartcomsolmphserver is not on the MATLAB path. ', ...
        'Check that cfg.comsol_mli_dir points to a LiveLink installation with this helper.']);
end

if cfg.verbose
    fprintf('[worker-init] Starting isolated COMSOL server from %s\n', comsol_root);
end

try
    server_port = mphstartcomsolmphserver( ...
        'comsolpath', comsol_root, ...
        'silent', 'on');
catch ME
    errorWithCode('SERVER_START_FAILED', ...
        'Failed to start COMSOL server from %s: %s', comsol_root, ME.message);
end

if cfg.verbose
    fprintf('[worker-init] Started isolated COMSOL server on %s:%d\n', host, server_port);
end

try
    mphstart(host, server_port, comsol_root);
catch ME
    errorWithCode('SERVER_CONNECT_FAILED', ...
        'Started COMSOL server on port %d but mphstart failed: %s', server_port, ME.message);
end
end

function ensureModelUtilAvailable()
try
    import com.comsol.model.util.*
    ModelUtil.tags();
catch ME
    errorWithCode('MODELUTIL_UNAVAILABLE', ...
        'COMSOL Java API ModelUtil is unavailable after mphstart: %s', ME.message);
end
end

function tf = hasLiveLinkConnection()
tf = false;
try
    import com.comsol.model.util.*
    ModelUtil.tags();
    tf = true;
catch
end
end

function tf = hasCallableSymbol(name)
symbol_type = exist(name, 'file');
tf = any(symbol_type == [2, 3, 6]);
end

function value = resolveConfigString(cfg, field_name, default_value)
value = default_value;
if isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    value = char(string(cfg.(field_name)));
end
end

function value = resolveConfigNumeric(cfg, field_name, default_value)
value = default_value;
if isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    value = cfg.(field_name);
end
end

function comsol_root = resolveComsolRoot(cfg)
if ~isfield(cfg, 'comsol_root') || isempty(cfg.comsol_root)
    errorWithCode('COMSOL_ROOT_NOT_CONFIGURED', ...
        'cfg.comsol_root is empty. Set it to the COMSOL Multiphysics root directory.');
end
comsol_root = char(string(cfg.comsol_root));
if exist(comsol_root, 'dir') ~= 7
    errorWithCode('COMSOL_ROOT_MISSING', ...
        'cfg.comsol_root does not exist: %s', comsol_root);
end
end

function errorWithCode(code, varargin)
message = sprintf(varargin{:});
error('run_band_dataset_worker:%s', code, '[%s] %s', code, message);
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

ok = createLockDirectory(lock_file);
if ~ok
    if exist(lock_file, 'dir')
        claimed = false;
        return;
    end
    error('run_band_dataset_worker:LockOpenFailed', ...
        'Cannot create lock directory %s.', lock_file);
end
claimed = true;

claim_info = fullfile(lock_file, 'claim.txt');
fid = fopen(claim_info, 'w');
if fid >= 0
    fprintf(fid, 'worker=%d\nsource=%s\n', worker_id, tensor_file);
    fclose(fid);
end

if cfg.verbose
    fprintf('[worker %d] claimed %s\n', worker_id, case_id);
end
end

function finalizeLock(lock_file, status_text)
[case_output_dir, ~, ~] = fileparts(lock_file);
done_file = fullfile(case_output_dir, '.done');
fid = fopen(done_file, 'w');
if fid >= 0
    fprintf(fid, '%s\n', status_text);
    fclose(fid);
end
if exist(lock_file, 'dir')
    rmdir(lock_file, 's');
end
end

function ok = createLockDirectory(lock_file)
ok = false;

if usejava('jvm')
    lock_dir = java.io.File(lock_file);
    ok = lock_dir.mkdir();
    return;
end

[status, msg] = mkdir(lock_file);
if status && ~contains(msg, 'already exists', 'IgnoreCase', true)
    ok = true;
end
end
