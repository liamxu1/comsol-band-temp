function summary = run_band_dataset_worker(config_or_file)
%RUN_BAND_DATASET_WORKER Process one shared batch queue as a single worker.

cfg = normalizeConfig(config_or_file);
AddAcousticBandPaths();

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

task_files = listTensorFiles(cfg);
worker_id = resolveWorkerId(cfg);
pid_cleanup = registerWorkerPid(cfg, resolveCurrentProcessId());
state = initializeWorkerState(worker_id);
state = initializeWorkerComsol(cfg, state);

summary = struct();
summary.worker_id = worker_id;
summary.output_dir = cfg.output_dir;
summary.worker_exit_reason = '';
collect_record_history = nargout > 0;
if collect_record_history
    summary.records = repmat(buildCaseRecord('', ''), 0, 1);
else
    summary.records = struct([]);
end
summary.completed = 0;
summary.ok_count = 0;
summary.error_count = 0;
claim_state = struct( ...
    'mode', 'cursor', ...
    'rescan_next_index', 1, ...
    'rescan_passes_started', 0);

while true

    if cfg.worker_healthcheck_before_claim
        [state, ready, exit_reason] = ensureWorkerReadyForClaim(cfg, state);
        if ~ready
            summary.worker_exit_reason = exit_reason;
            break;
        end
    end

    [claimed, lock_file, case_id, tensor_file, attempt_count, claim_state] = claimNextCase( ...
        task_files, cfg, worker_id, claim_state);
    if ~claimed
        break;
    end

    record = buildCaseRecord(case_id, tensor_file);
    record.attempt_count = attempt_count;
    maybeUpdateBatchSummaryRecord(cfg, record, worker_id, true, false, false);

    [record, state, stop_worker] = runClaimedCaseWithRecovery( ...
        tensor_file, cfg, state, lock_file, record);

    if collect_record_history
        summary.records(end + 1, 1) = record; %#ok<AGROW>
    end
    summary.completed = summary.completed + 1;
    if strcmp(record.status, 'ok')
        summary.ok_count = summary.ok_count + 1;
    elseif strcmp(record.status, 'error')
        summary.error_count = summary.error_count + 1;
    end
    if cfg.verbose
        fprintf('[worker %d] %s | %s | %.2f s\n', ...
            worker_id, case_id, record.status, record.elapsed_s);
    end
    maybeUpdateBatchSummaryRecord( ...
        cfg, ...
        record, ...
        worker_id, ...
        false, ...
        true, ...
        exist(record.dataset_file, 'file') == 2);

    if stop_worker
        summary.worker_exit_reason = record.worker_exit_reason;
        break;
    end

    if strcmp(record.status, 'ok')
        [state, recycled_ok, recycle_message] = maybeRecycleComsolAfterCase( ...
            cfg, state, record.case_id);
        if ~recycled_ok
            summary.worker_exit_reason = sprintf( ...
                'Periodic COMSOL recycle failed after case %s: %s', ...
                record.case_id, recycle_message);
            break;
        end
    end
end

maybeRefreshBatchSummarySnapshotNow(cfg);

if ~isempty(summary.worker_exit_reason)
    fprintf('[worker %d] WORKER_INFRA_RECOVERY_FAILED %s\n', ...
        worker_id, summary.worker_exit_reason);
    fprintf('[worker %d] WORKER_EXITING_NO_MORE_CLAIMS\n', worker_id);
    errorWithCode('WORKER_INFRA_RECOVERY_FAILED', ...
        'WORKER_EXITING_NO_MORE_CLAIMS: %s', summary.worker_exit_reason);
end
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

function pid = resolveCurrentProcessId()
pid = [];
try
    pid = feature('getpid');
catch
end
end

function cleanup = registerWorkerPid(cfg, pid)
cleanup = [];
if isempty(pid) || ~isfinite(pid) || pid <= 0
    return;
end

registry_dir = fullfile(cfg.output_dir, '.worker_pids');
if exist(registry_dir, 'dir') ~= 7
    mkdir(registry_dir);
end

pid_file = fullfile(registry_dir, sprintf('worker_%d.pid', round(pid)));
fid = fopen(pid_file, 'w');
if fid >= 0
    fprintf(fid, 'pid=%d\n', round(pid));
    fprintf(fid, 'created_at=%s\n', char(datetime('now', 'TimeZone', 'local', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX')));
    fclose(fid);
end

cleanup = onCleanup(@() deleteWorkerPidFile(pid_file));
end

function deleteWorkerPidFile(pid_file)
if exist(pid_file, 'file') == 2
    delete(pid_file);
end
end

function state = initializeWorkerState(worker_id)
state = struct();
state.worker_id = worker_id;
state.server_port = [];
state.server_kind = 'unknown';
state.recovery_attempts_total = 0;
state.consecutive_infra_failures = 0;
state.last_healthcheck_ok = false;
state.last_infra_message = '';
state.comsol_mli_loaded = false;
state.completed_case_count = 0;
end

function record = buildCaseRecord(case_id, tensor_file)
record = struct( ...
    'case_id', case_id, ...
    'tensor_file', tensor_file, ...
    'status', 'running', ...
    'elapsed_s', NaN, ...
    'dataset_file', '', ...
    'message', '', ...
    'failure_kind', '', ...
    'infra_recovery_attempts', 0, ...
    'worker_exit_reason', '', ...
    'attempt_count', 0);
end

function [record, state, stop_worker] = runClaimedCaseWithRecovery( ...
        tensor_file, cfg, state, lock_file, record)
stop_worker = false;
t_start = tic;
infra_retry_count = 0;

while true
    try
        result = runOneTensorCase(tensor_file, cfg, record.case_id);
        record.status = 'ok';
        record.elapsed_s = toc(t_start);
        record.dataset_file = result.dataset_file;
        record.message = '';
        record.failure_kind = '';
        record.worker_exit_reason = '';
        state.consecutive_infra_failures = 0;
        state.last_healthcheck_ok = true;
        state.completed_case_count = state.completed_case_count + 1;
        finalizeLock(lock_file, record);
        return;
    catch ME
        record.elapsed_s = toc(t_start);
        record.dataset_file = '';
        [failure_kind, message] = classifyFailure(ME);
        record.failure_kind = failure_kind;
        record.message = message;

        if ~strcmp(failure_kind, 'infrastructure')
            record.status = 'error';
            state.consecutive_infra_failures = 0;
            finalizeLock(lock_file, record);
            return;
        end

        state.consecutive_infra_failures = state.consecutive_infra_failures + 1;
        state.last_healthcheck_ok = false;
        state.last_infra_message = message;

        if shouldStopForInfraFailure(cfg, state)
            record.status = 'error';
            record.worker_exit_reason = sprintf( ...
                'Consecutive infrastructure failures reached limit (%d): %s', ...
                cfg.worker_infra_failure_limit, message);
            finalizeLock(lock_file, record);
            stop_worker = true;
            return;
        end

        if ~cfg.enable_worker_comsol_recovery
            record.status = 'error';
            record.worker_exit_reason = sprintf( ...
                'Infrastructure failure detected and recovery is disabled: %s', ...
                message);
            finalizeLock(lock_file, record);
            stop_worker = true;
            return;
        end

        if infra_retry_count >= cfg.case_infra_retry_limit
            record.status = 'error';
            record.worker_exit_reason = sprintf( ...
                'Infrastructure failure persisted after %d retries: %s', ...
                cfg.case_infra_retry_limit, message);
            finalizeLock(lock_file, record);
            stop_worker = true;
            return;
        end

        [state, recovered, recovery_message] = recoverWorkerComsol(cfg, state, ...
            sprintf('case %s failure', record.case_id));
        record.infra_recovery_attempts = record.infra_recovery_attempts + 1;
        infra_retry_count = infra_retry_count + 1;

        if ~recovered
            record.status = 'error';
            record.worker_exit_reason = sprintf( ...
                'COMSOL recovery failed after %s: %s', ...
                record.case_id, recovery_message);
            finalizeLock(lock_file, record);
            stop_worker = true;
            return;
        end

        if cfg.verbose
            fprintf('[worker %d] recovered COMSOL session; retrying %s\n', ...
                state.worker_id, record.case_id);
        end
    end
end
end

function [claimed, lock_file, case_id, tensor_file, attempt_count, claim_state] = claimNextCase( ...
        task_files, cfg, worker_id, claim_state)
claimed = false;
lock_file = '';
case_id = '';
tensor_file = '';
attempt_count = 0;

if strcmpi(claim_state.mode, 'cursor')
    [claimed, lock_file, case_id, tensor_file, attempt_count, exhausted] = ...
        claimNextCaseFromCursor(task_files, cfg, worker_id);
    if claimed
        return;
    end
    if exhausted
        max_rescan_passes = max(0, floor(resolveConfigNumeric(cfg, ...
            'tail_rescan_max_passes', 1)));
        if max_rescan_passes <= 0
            return;
        end
        claim_state.mode = 'rescan';
        claim_state.rescan_next_index = 1;
        claim_state.rescan_passes_started = 1;
    end
end

if strcmpi(claim_state.mode, 'rescan')
    max_rescan_passes = max(0, floor(resolveConfigNumeric(cfg, ...
        'tail_rescan_max_passes', 1)));
    while claim_state.rescan_passes_started > 0 && ...
            claim_state.rescan_passes_started <= max_rescan_passes
        [claimed, lock_file, case_id, tensor_file, attempt_count, exhausted, next_index] = ...
            tryClaimAnyCaseByScan(task_files, cfg, worker_id, ...
            claim_state.rescan_next_index);
        claim_state.rescan_next_index = next_index;
        if claimed
            return;
        end
        if ~exhausted
            return;
        end
        claim_state.rescan_passes_started = claim_state.rescan_passes_started + 1;
        claim_state.rescan_next_index = 1;
    end
end
end

function [claimed, lock_file, case_id, tensor_file, attempt_count, exhausted] = ...
        claimNextCaseFromCursor(task_files, cfg, worker_id)
claimed = false;
lock_file = '';
case_id = '';
tensor_file = '';
attempt_count = 0;
exhausted = false;
task_count = numel(task_files);

while true
    [task_index, exhausted] = reserveNextTaskIndex(cfg, task_count);
    if exhausted
        return;
    end

    tensor_file = task_files{task_index};
    [claimed, lock_file, case_id, attempt_count] = tryClaimCase( ...
        tensor_file, cfg, worker_id);
    if claimed
        return;
    end
end
end

function [claimed, lock_file, case_id, tensor_file, attempt_count, exhausted, next_index] = ...
        tryClaimAnyCaseByScan(task_files, cfg, worker_id, start_index)
claimed = false;
lock_file = '';
case_id = '';
tensor_file = '';
attempt_count = 0;
exhausted = false;

if nargin < 4 || isempty(start_index)
    start_index = 1;
end
next_index = start_index;

for i = start_index:numel(task_files)
    candidate_file = task_files{i};
    [claimed, lock_file, case_id, attempt_count] = tryClaimCase( ...
        candidate_file, cfg, worker_id);
    next_index = i + 1;
    if claimed
        tensor_file = candidate_file;
        return;
    end
end
exhausted = true;
end

function [task_index, exhausted] = reserveNextTaskIndex(cfg, task_count)
task_index = [];
exhausted = false;

cursor_lock_file = fullfile(cfg.output_dir, '.task_cursor.lock');
cursor_file = fullfile(cfg.output_dir, '.task_cursor.txt');
cleanup = acquireLocalLock(cursor_lock_file);
next_index = readScalarCounter(cursor_file, 1);

if next_index > task_count
    exhausted = true;
    clear cleanup;
    return;
end

task_index = next_index;
writeScalarCounter(cursor_file, next_index + 1);
clear cleanup;
end

function [state, ready, exit_reason] = ensureWorkerReadyForClaim(cfg, state)
ready = true;
exit_reason = '';

try
    state = ensureWorkerComsolHealthy(cfg, state);
    state.consecutive_infra_failures = 0;
    state.last_healthcheck_ok = true;
catch ME
    [failure_kind, message] = classifyFailure(ME);
    state.consecutive_infra_failures = state.consecutive_infra_failures + 1;
    state.last_healthcheck_ok = false;
    state.last_infra_message = message;

    if shouldStopForInfraFailure(cfg, state)
        ready = false;
        exit_reason = sprintf( ...
            'Health check failed and infrastructure failure limit reached: %s', ...
            message);
        return;
    end

    if ~cfg.enable_worker_comsol_recovery
        ready = false;
        exit_reason = sprintf( ...
            'Health check failed and recovery is disabled: %s', message);
        return;
    end

    [state, recovered, recovery_message] = recoverWorkerComsol(cfg, state, ...
        'pre-claim health check');
    if ~recovered
        ready = false;
        exit_reason = sprintf('Health check recovery failed: %s', recovery_message);
        return;
    end

    state.consecutive_infra_failures = 0;
    state.last_healthcheck_ok = true;
end
end

function tf = shouldStopForInfraFailure(cfg, state)
tf = cfg.worker_infra_failure_limit > 0 && ...
    state.consecutive_infra_failures >= cfg.worker_infra_failure_limit;
end

function [state, recycled_ok, recycle_message] = maybeRecycleComsolAfterCase(cfg, state, case_id)
recycled_ok = true;
recycle_message = '';
restart_every = resolveConfigNumeric(cfg, 'worker_restart_comsol_every_n_cases', 0);
if restart_every <= 0
    return;
end
if mod(state.completed_case_count, restart_every) ~= 0
    return;
end

if cfg.verbose
    fprintf('[worker %d] recycling COMSOL session after %d completed cases (last case: %s)\n', ...
        state.worker_id, state.completed_case_count, case_id);
end

[state, recovered, recovery_message] = recoverWorkerComsol(cfg, state, ...
    sprintf('periodic recycle after %d completed cases', state.completed_case_count));
if ~recovered
    recycled_ok = false;
    recycle_message = recovery_message;
end
end

function state = initializeWorkerComsol(cfg, state)
if cfg.verbose
    fprintf('[worker-init] mode=manual COMSOL-with-MATLAB host + per-worker isolated server\n');
end

state = ensureComsolMliLoaded(cfg, state, true);

if hasLiveLinkConnection()
    if cfg.verbose
        fprintf('[worker-init] Existing COMSOL LiveLink session detected; reusing current connection\n');
        fprintf('[worker-init] LIVELINK_INIT_OK\n');
    end
    state.last_healthcheck_ok = true;
    if cfg.comsol_reuse_existing_server
        state.server_port = resolveConfigNumeric(cfg, 'comsol_port', 2036);
        state.server_kind = 'shared';
    end
    return;
end

if ~hasCallableSymbol('mphstart')
    errorWithCode('MPHSTART_UNAVAILABLE', ...
        ['COMSOL LiveLink function mphstart is not available after adding ', ...
        'cfg.comsol_mli_dir: %s'], cfg.comsol_mli_dir);
end

if cfg.comsol_reuse_existing_server
    state = connectSharedServer(cfg, state);
else
    state = startIsolatedServer(cfg, state);
end

ensureModelUtilAvailable();
state.last_healthcheck_ok = true;

if cfg.verbose
    fprintf('[worker-init] LIVELINK_INIT_OK\n');
end
end

function state = ensureWorkerComsolHealthy(cfg, state)
state = ensureComsolMliLoaded(cfg, state, false);

if ~hasCallableSymbol('mphstart')
    errorWithCode('MPHSTART_UNAVAILABLE', ...
        'COMSOL LiveLink function mphstart is unavailable during health check.');
end

if ~hasLiveLinkConnection()
    errorWithCode('SERVER_CONNECTION_LOST', ...
        'COMSOL LiveLink connection is not available in the worker.');
end

ensureModelUtilAvailable();
state.last_healthcheck_ok = true;
end

function [state, recovered, recovery_message] = recoverWorkerComsol(cfg, state, reason)
recovered = false;
recovery_message = '';
state.recovery_attempts_total = state.recovery_attempts_total + 1;

if cfg.verbose
    fprintf('[worker %d] attempting COMSOL recovery after %s\n', ...
        state.worker_id, reason);
end

resetWorkerComsolSession(cfg, state);

backoff_s = resolveConfigNumeric(cfg, 'worker_recovery_backoff_s', 0);
if backoff_s > 0
    pause(backoff_s);
end

try
    state = initializeWorkerComsol(cfg, state);
    state.consecutive_infra_failures = 0;
    state.last_healthcheck_ok = true;
    recovered = true;
catch ME
    [~, recovery_message] = classifyFailure(ME);
    state.last_infra_message = recovery_message;
end
end

function resetWorkerComsolSession(cfg, state)
try
    import com.comsol.model.util.*
    tags_java = ModelUtil.tags();
    tags = cell(tags_java);
    for i = 1:numel(tags)
        try
            ModelUtil.remove(tags{i});
        catch
        end
    end
    try
        ModelUtil.disconnect();
    catch
    end
    try
        ModelUtil.clear();
    catch
    end
catch
end

if ~cfg.comsol_reuse_existing_server
    terminateIsolatedComsolServer(state);
end
end

function state = ensureComsolMliLoaded(cfg, state, verbose_log)
if isfield(state, 'comsol_mli_loaded') && state.comsol_mli_loaded
    return;
end

if ~isfield(cfg, 'comsol_mli_dir') || isempty(cfg.comsol_mli_dir)
    errorWithCode('MLI_NOT_CONFIGURED', ...
        'cfg.comsol_mli_dir is empty. Set it to the COMSOL LiveLink mli directory.');
end
if exist(cfg.comsol_mli_dir, 'dir') ~= 7
    errorWithCode('MLI_DIR_MISSING', ...
        'cfg.comsol_mli_dir does not exist: %s', cfg.comsol_mli_dir);
end
addpath(cfg.comsol_mli_dir);
state.comsol_mli_loaded = true;
if verbose_log && cfg.verbose
    fprintf('[worker-init] Added COMSOL mli path: %s\n', cfg.comsol_mli_dir);
    fprintf('[worker-init] which mphstart => %s\n', strtrim(which('mphstart')));
    fprintf('[worker-init] which mphstartcomsolmphserver => %s\n', ...
        strtrim(which('mphstartcomsolmphserver')));
end
end

function state = connectSharedServer(cfg, state)
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

state.server_port = port;
state.server_kind = 'shared';
end

function state = startIsolatedServer(cfg, state)
comsol_root = resolveComsolRoot(cfg);
host = resolveConfigString(cfg, 'comsol_host', '127.0.0.1');
comsol_np = resolveConfigNumeric(cfg, 'comsol_np', 0);
hide_server_window = false;
if ispc
    hide_server_window = resolveConfigLogical(cfg, 'comsol_hide_server_window', true);
end
startup_lock = fullfile(cfg.output_dir, '.comsol_server_start.lock');
startup_timeout_s = resolveConfigNumeric(cfg, 'comsol_server_start_lock_timeout_s', 300);
retry_limit = resolveConfigNumeric(cfg, 'comsol_server_start_retry_limit', 4);
retry_backoff_s = resolveConfigNumeric(cfg, 'comsol_server_start_retry_backoff_s', 3);

if ~hasCallableSymbol('mphstartcomsolmphserver')
    errorWithCode('SERVER_HELPER_MISSING', ...
        ['COMSOL helper mphstartcomsolmphserver is not on the MATLAB path. ', ...
        'Check that cfg.comsol_mli_dir points to a LiveLink installation with this helper.']);
end

if cfg.verbose
    fprintf('[worker-init] Starting isolated COMSOL server from %s\n', comsol_root);
end

startup_cleanup = acquireLocalLockWithTimeout(startup_lock, startup_timeout_s);

for attempt = 1:(retry_limit + 1)
    server_port = [];

    try
        start_args = {'comsolpath', comsol_root, 'silent', 'on'};
        if comsol_np > 0
            start_args = [start_args, {'np', comsol_np}];
        end
        if ispc && hide_server_window
            start_args = [start_args, {'hide', 'on'}];
        end
        server_port = mphstartcomsolmphserver(start_args{:});

        if cfg.verbose
            if comsol_np > 0
                if ispc && hide_server_window
                    fprintf('[worker-init] Started isolated COMSOL server on %s:%d with np=%d hide=on\n', ...
                        host, server_port, comsol_np);
                else
                    fprintf('[worker-init] Started isolated COMSOL server on %s:%d with np=%d\n', ...
                        host, server_port, comsol_np);
                end
            else
                if ispc && hide_server_window
                    fprintf('[worker-init] Started isolated COMSOL server on %s:%d hide=on\n', host, server_port);
                else
                    fprintf('[worker-init] Started isolated COMSOL server on %s:%d\n', host, server_port);
                end
            end
        end

        mphstart(host, server_port, comsol_root);
        state.server_port = server_port;
        state.server_kind = 'isolated';
        clear startup_cleanup;
        return;
    catch ME
        if ~isempty(server_port) && isfinite(server_port)
            terminateIsolatedComsolServer(struct('server_port', server_port));
        end

        if attempt > retry_limit
            [~, message] = classifyFailure(ME);
            errorWithCode('SERVER_START_FAILED', ...
                ['Failed to start/connect isolated COMSOL server after %d attempts ', ...
                '(last error: %s)'], attempt, message);
        end

        if cfg.verbose
            fprintf('[worker-init] isolated server startup attempt %d/%d failed; retrying in %.1f s\n', ...
                attempt, retry_limit + 1, retry_backoff_s);
        end

        if retry_backoff_s > 0
            pause(retry_backoff_s);
        end
    end
end

end

function terminateIsolatedComsolServer(state)
port = [];
if isfield(state, 'server_port') && ~isempty(state.server_port)
    port = state.server_port;
end
if isempty(port) || ~isfinite(port)
    return;
end

pids = findListeningPidsByPort(port);
for i = 1:numel(pids)
    killProcessByPid(pids(i));
end
end

function pids = findListeningPidsByPort(port)
pids = [];

if ispc
    [status, output] = system(sprintf('netstat -ano -p tcp | findstr ":%d"', port));
    if status ~= 0 || isempty(strtrim(output))
        return;
    end
    lines = regexp(output, '\r?\n', 'split');
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if isempty(line)
            continue;
        end
        if isempty(regexpi(line, '\<LISTENING\>'))
            continue;
        end
        tokens = regexp(line, '\s+(\d+)\s*$', 'tokens', 'once');
        if isempty(tokens)
            continue;
        end
        pid = str2double(tokens{1});
        if isfinite(pid) && pid > 0
            pids(end + 1) = pid; %#ok<AGROW>
        end
    end
else
    [status, output] = system(sprintf('lsof -nP -iTCP:%d -sTCP:LISTEN -t', port));
    if status ~= 0 || isempty(strtrim(output))
        return;
    end
    vals = sscanf(output, '%d');
    pids = vals(:).';
end

if ~isempty(pids)
    pids = unique(pids);
end
end

function killProcessByPid(pid)
if ~isfinite(pid) || pid <= 0
    return;
end

if ispc
    system(sprintf('taskkill /PID %d /T /F >NUL 2>&1', round(pid)));
else
    system(sprintf('kill -TERM %d >/dev/null 2>&1', round(pid)));
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

function value = resolveConfigLogical(cfg, field_name, default_value)
value = default_value;
if isfield(cfg, field_name) && ~isempty(cfg.(field_name))
    value = logical(cfg.(field_name));
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
error(sprintf('run_band_dataset_worker:%s', code), '[%s] %s', code, message);
end

function [failure_kind, message] = classifyFailure(ME)
message = sanitizeDoneValue(getReport(ME, 'basic', 'hyperlinks', 'off'));
identifier = char(string(ME.identifier));
combined = lower([identifier, ' ', message]);

infra_identifiers = { ...
    'run_band_dataset_worker:server_connect_failed', ...
    'run_band_dataset_worker:server_start_failed', ...
    'run_band_dataset_worker:server_connection_lost', ...
    'run_band_dataset_worker:modelutil_unavailable', ...
    'run_band_dataset_worker:mphstart_unavailable', ...
    'run_band_dataset_worker:mli_not_configured', ...
    'run_band_dataset_worker:mli_dir_missing', ...
    'run_band_dataset_worker:server_helper_missing', ...
    'run_band_dataset_worker:comsol_root_not_configured', ...
    'run_band_dataset_worker:comsol_root_missing', ...
    'run_band_dataset_worker:worker_infra_recovery_failed'};

infra_patterns = { ...
    'failed to connect', ...
    'connection refused', ...
    'broken pipe', ...
    'connectexception', ...
    'java heap space', ...
    'outofmemory', ...
    'out of memory', ...
    'unable to allocate memory', ...
    'insufficient memory', ...
    'server connection lost', ...
    'comsol server is not available', ...
    'livelink connection is not available', ...
    'modelutil is unavailable'};

lower_identifier = lower(identifier);
if any(strcmp(lower_identifier, infra_identifiers))
    failure_kind = 'infrastructure';
elseif any(contains(combined, infra_patterns))
    failure_kind = 'infrastructure';
else
    failure_kind = 'case';
end
end

function result = runOneTensorCase(tensor_file, cfg, case_id)
symmetry_group = InferBsplineSymmetryGroup(case_id);
task_sequence_index = resolveTaskSequenceIndex(cfg, tensor_file, case_id);

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
    'split_band_and_fields_files', cfg.split_band_and_fields_files, ...
    'save_fields_for_sample_stride', cfg.save_fields_for_sample_stride, ...
    'save_fields_for_sample_offset', cfg.save_fields_for_sample_offset, ...
    'field_sample_count', cfg.field_sample_count, ...
    'field_sample_k_bins', cfg.field_sample_k_bins, ...
    'field_sample_band_bins', cfg.field_sample_band_bins, ...
    'field_output_grid_resolution', cfg.field_output_grid_resolution, ...
    'field_output_dtype', cfg.field_output_dtype, ...
    'field_sampling_mode', cfg.field_sampling_mode, ...
    'task_sequence_index', task_sequence_index, ...
    'verbose', cfg.verbose);

result = RunAcousticBandFromTensor(tensor_file, symmetry_group, ...
    cfg.unit_cell_length, band_cfg);
end

function task_sequence_index = resolveTaskSequenceIndex(cfg, tensor_file, case_id)
task_sequence_index = [];

if isfield(cfg, 'task_sequence_index_map') && isstruct(cfg.task_sequence_index_map)
    map_struct = cfg.task_sequence_index_map;
    case_key = matlab.lang.makeValidName(case_id);
    tensor_key = matlab.lang.makeValidName(regexprep(char(string(tensor_file)), '[^A-Za-z0-9_]', '_'));
    if isfield(map_struct, case_key)
        task_sequence_index = map_struct.(case_key);
        return;
    end
    if isfield(map_struct, tensor_key)
        task_sequence_index = map_struct.(tensor_key);
        return;
    end
end

if isfield(cfg, 'tensor_files') && ~isempty(cfg.tensor_files)
    files = cellstr(cfg.tensor_files(:));
    match_index = find(strcmp(files, tensor_file), 1);
    if ~isempty(match_index)
        task_sequence_index = match_index;
    end
end
end

function files = listTensorFiles(cfg)
selection = ResolveTensorTaskSelection(cfg);
files = selection.selected_files;
end

function worker_id = resolveWorkerId(cfg)
if ~isempty(cfg.worker_id)
    worker_id = cfg.worker_id;
else
    worker_id = feature('getpid');
end
end

function [claimed, lock_file, case_id, attempt_count] = tryClaimCase(tensor_file, cfg, worker_id)
[~, base] = fileparts(tensor_file);
case_id = regexprep(base, '_tensor$', '');
if ~isempty(cfg.case_name_suffix)
    case_id = [case_id, cfg.case_name_suffix];
end

claimed = false;
lock_file = '';
attempt_count = 0;

case_output_dir = fullfile(cfg.output_dir, case_id);
dataset_file = fullfile(case_output_dir, [case_id, '_band.mat']);
done_file = fullfile(case_output_dir, '.done');
done_info = readDoneMetadata(done_file);
lock_file = fullfile(case_output_dir, '.lock');

if cfg.skip_completed && exist(dataset_file, 'file') && exist(done_file, 'file')
    return;
end

max_case_attempts = max(1, floor(resolveConfigNumeric(cfg, 'max_case_attempts', 3)));
if done_info.attempt_count >= max_case_attempts
    return;
end

if ~exist(case_output_dir, 'dir')
    mkdir(case_output_dir);
end

ok = createLockDirectory(lock_file);
if ~ok
    if exist(lock_file, 'dir')
        return;
    end
    error('run_band_dataset_worker:LockOpenFailed', ...
        'Cannot create lock directory %s.', lock_file);
end
claimed = true;
attempt_count = done_info.attempt_count + 1;

claim_info = fullfile(lock_file, 'claim.txt');
fid = fopen(claim_info, 'w');
if fid >= 0
    fprintf(fid, 'worker=%d\nsource=%s\nattempt_count=%d\n', ...
        worker_id, tensor_file, attempt_count);
    fclose(fid);
end

if cfg.verbose
    fprintf('[worker %d] claimed %s (attempt %d)\n', ...
        worker_id, case_id, attempt_count);
end
end

function finalizeLock(lock_file, record)
[case_output_dir, ~, ~] = fileparts(lock_file);
done_file = fullfile(case_output_dir, '.done');
fid = fopen(done_file, 'w');
if fid >= 0
    fprintf(fid, 'status=%s\n', record.status);
    fprintf(fid, 'elapsed_s=%.6f\n', record.elapsed_s);
    fprintf(fid, 'dataset_file=%s\n', record.dataset_file);
    fprintf(fid, 'failure_kind=%s\n', record.failure_kind);
    fprintf(fid, 'infra_recovery_attempts=%d\n', record.infra_recovery_attempts);
    fprintf(fid, 'attempt_count=%d\n', record.attempt_count);
    fprintf(fid, 'worker_exit_reason=%s\n', sanitizeDoneValue(record.worker_exit_reason));
    fprintf(fid, 'message=%s\n', sanitizeDoneValue(record.message));
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

function info = readDoneMetadata(done_file)
info = struct('status', '', 'attempt_count', 0);
if exist(done_file, 'file') ~= 2
    return;
end

fid = fopen(done_file, 'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid));
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    tokens = regexp(strtrim(line), '^([A-Za-z0-9_]+)=(.*)$', 'tokens', 'once');
    if isempty(tokens)
        continue;
    end
    key = char(tokens{1});
    value = char(tokens{2});
    switch key
        case 'status'
            info.status = value;
        case 'attempt_count'
            parsed = str2double(value);
            if isfinite(parsed) && parsed > 0
                info.attempt_count = floor(parsed);
            end
    end
end
clear cleanup;

if info.attempt_count <= 0 && ~isempty(info.status)
    info.attempt_count = 1;
end
end

function updateBatchSummaryRecord(cfg, record, worker_id, has_lock, has_done, has_band_mat)
summary_file = fullfile(cfg.output_dir, 'batch_summary.csv');
events_file = fullfile(cfg.output_dir, 'batch_summary_events.csv');
lock_file = fullfile(cfg.output_dir, '.batch_summary.lock');
event_count_file = fullfile(cfg.output_dir, '.batch_summary_event_count.txt');
snapshot_marker_file = fullfile(cfg.output_dir, '.batch_summary_snapshot_event_count.txt');
cleanup = acquireLocalLock(lock_file);

bootstrapBatchSummaryEvents(summary_file, events_file, event_count_file, snapshot_marker_file);

row = buildBatchSummaryRow(record, worker_id, has_lock, has_done, has_band_mat);
appendBatchSummaryRow(events_file, row);
event_count = readScalarCounter(event_count_file, 0) + 1;
writeScalarCounter(event_count_file, event_count);

if shouldRefreshBatchSummarySnapshot(cfg, has_done, event_count, summary_file, snapshot_marker_file)
    refreshBatchSummarySnapshot(summary_file, events_file);
    writeScalarCounter(snapshot_marker_file, event_count);
end
clear cleanup;
end

function maybeUpdateBatchSummaryRecord(cfg, record, worker_id, has_lock, has_done, has_band_mat)
enabled = false;
if isfield(cfg, 'enable_batch_summary') && ~isempty(cfg.enable_batch_summary)
    enabled = logical(cfg.enable_batch_summary);
end
if ~enabled
    return;
end
updateBatchSummaryRecord(cfg, record, worker_id, has_lock, has_done, has_band_mat);
end

function bootstrapBatchSummaryEvents( ...
        summary_file, events_file, event_count_file, snapshot_marker_file)
if exist(events_file, 'file') == 2 || exist(summary_file, 'file') ~= 2
    return;
end

rows = readBatchSummaryRows(summary_file);
if isempty(rows)
    writeScalarCounter(event_count_file, 0);
    writeScalarCounter(snapshot_marker_file, 0);
    return;
end

writeBatchSummaryRows(events_file, rows);
bootstrap_count = size(rows, 1);
writeScalarCounter(event_count_file, bootstrap_count);
writeScalarCounter(snapshot_marker_file, bootstrap_count);
end

function appendBatchSummaryRow(summary_file, row)
write_header = exist(summary_file, 'file') ~= 2;
fid = fopen(summary_file, 'a');
if fid < 0
    error('run_band_dataset_worker:BatchSummaryOpenFailed', ...
        'Cannot open batch summary file for appending: %s', summary_file);
end
cleanup = onCleanup(@() fclose(fid));

if write_header
    fprintf(fid, ['case_id,status,worker_id,has_lock,has_done,has_band_mat,elapsed_s,', ...
        'dataset_file,message,tensor_file,failure_kind,infra_recovery_attempts,', ...
        'worker_exit_reason\n']);
end

fprintf(fid, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
    csvField(row{1}), ...
    csvField(row{2}), ...
    csvField(row{3}), ...
    csvField(row{4}), ...
    csvField(row{5}), ...
    csvField(row{6}), ...
    csvField(row{7}), ...
    csvField(row{8}), ...
    csvField(row{9}), ...
    csvField(row{10}), ...
    csvField(row{11}), ...
    csvField(row{12}), ...
    csvField(row{13}));
clear cleanup;
end

function tf = shouldRefreshBatchSummarySnapshot( ...
        cfg, has_done, event_count, summary_file, snapshot_marker_file)
tf = false;
if exist(summary_file, 'file') ~= 2
    tf = true;
    return;
end
if ~has_done
    return;
end

refresh_every = resolveConfigNumeric(cfg, 'batch_summary_snapshot_every_n_events', 40);
refresh_every = max(1, round(refresh_every));
last_snapshot_event_count = readScalarCounter(snapshot_marker_file, 0);
tf = (event_count - last_snapshot_event_count) >= refresh_every;
end

function refreshBatchSummarySnapshotNow(cfg)
summary_file = fullfile(cfg.output_dir, 'batch_summary.csv');
events_file = fullfile(cfg.output_dir, 'batch_summary_events.csv');
lock_file = fullfile(cfg.output_dir, '.batch_summary.lock');
snapshot_marker_file = fullfile(cfg.output_dir, '.batch_summary_snapshot_event_count.txt');
event_count_file = fullfile(cfg.output_dir, '.batch_summary_event_count.txt');

if exist(events_file, 'file') ~= 2
    return;
end

cleanup = acquireLocalLock(lock_file);
refreshBatchSummarySnapshot(summary_file, events_file);
writeScalarCounter(snapshot_marker_file, readScalarCounter(event_count_file, 0));
clear cleanup;
end

function maybeRefreshBatchSummarySnapshotNow(cfg)
enabled = false;
if isfield(cfg, 'enable_batch_summary') && ~isempty(cfg.enable_batch_summary)
    enabled = logical(cfg.enable_batch_summary);
end
if ~enabled
    return;
end
refreshBatchSummarySnapshotNow(cfg);
end

function refreshBatchSummarySnapshot(summary_file, events_file)
rows = readBatchSummaryRows(events_file);
rows = collapseBatchSummaryRows(rows);
writeBatchSummaryRows(summary_file, rows);
end

function rows = collapseBatchSummaryRows(event_rows)
column_count = 13;
rows = cell(0, column_count);
if isempty(event_rows)
    return;
end

case_index_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
for i = 1:size(event_rows, 1)
    row = event_rows(i, :);
    case_id = char(string(row{1}));
    if isKey(case_index_map, case_id)
        rows(case_index_map(case_id), :) = row;
    else
        rows(end + 1, :) = row; %#ok<AGROW>
        case_index_map(case_id) = size(rows, 1);
    end
end
end

function cleanup = acquireLocalLock(lock_file)
cleanup = acquireLocalLockWithTimeout(lock_file, inf);
end

function cleanup = acquireLocalLockWithTimeout(lock_file, timeout_s)
t_start = tic;
while true
    if createLockDirectory(lock_file)
        cleanup = onCleanup(@() releaseLocalLock(lock_file));
        return;
    end
    if isfinite(timeout_s) && toc(t_start) >= timeout_s
        error('run_band_dataset_worker:LockTimeout', ...
            'Timed out waiting for lock directory %s.', lock_file);
    end
    pause(0.1);
end
end

function releaseLocalLock(lock_file)
if exist(lock_file, 'dir') == 7
    rmdir(lock_file, 's');
end
end

function row = buildBatchSummaryRow(record, worker_id, has_lock, has_done, has_band_mat)
row = { ...
    record.case_id, ...
    record.status, ...
    workerIdText(worker_id), ...
    logicalText(has_lock), ...
    logicalText(has_done), ...
    logicalText(has_band_mat), ...
    numericText(record.elapsed_s), ...
    char(string(record.dataset_file)), ...
    sanitizeDoneValue(record.message), ...
    char(string(record.tensor_file)), ...
    char(string(record.failure_kind)), ...
    numericText(record.infra_recovery_attempts), ...
    sanitizeDoneValue(record.worker_exit_reason)};
end

function rows = readBatchSummaryRows(summary_file)
column_count = 13;
rows = cell(0, column_count);
if exist(summary_file, 'file') ~= 2
    return;
end

fid = fopen(summary_file, 'r');
if fid < 0
    error('run_band_dataset_worker:BatchSummaryOpenFailed', ...
        'Cannot open batch summary file for reading: %s', summary_file);
end
cleanup = onCleanup(@() fclose(fid));

fgetl(fid);
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    if isempty(line)
        continue;
    end
    row = parseCsvLine(line);
    if isempty(row)
        continue;
    end
    if numel(row) < column_count
        row(end + 1:column_count) = {''};
    elseif numel(row) > column_count
        row = row(1:column_count);
    end
    rows(end + 1, :) = row; %#ok<AGROW>
end
clear cleanup;
end

function writeBatchSummaryRows(summary_file, rows)
fid = fopen(summary_file, 'w');
if fid < 0
    error('run_band_dataset_worker:BatchSummaryOpenFailed', ...
        'Cannot open batch summary file for writing: %s', summary_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, ['case_id,status,worker_id,has_lock,has_done,has_band_mat,elapsed_s,', ...
    'dataset_file,message,tensor_file,failure_kind,infra_recovery_attempts,', ...
    'worker_exit_reason\n']);
for i = 1:size(rows, 1)
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n', ...
        csvField(rows{i, 1}), ...
        csvField(rows{i, 2}), ...
        csvField(rows{i, 3}), ...
        csvField(rows{i, 4}), ...
        csvField(rows{i, 5}), ...
        csvField(rows{i, 6}), ...
        csvField(rows{i, 7}), ...
        csvField(rows{i, 8}), ...
        csvField(rows{i, 9}), ...
        csvField(rows{i, 10}), ...
        csvField(rows{i, 11}), ...
        csvField(rows{i, 12}), ...
        csvField(rows{i, 13}));
end
clear cleanup;
end

function row = parseCsvLine(line)
row = {};
current = '';
in_quotes = false;
i = 1;
line_length = numel(line);

while i <= line_length
    ch = line(i);
    if ch == '"'
        if in_quotes && i < line_length && line(i + 1) == '"'
            current(end + 1) = '"'; %#ok<AGROW>
            i = i + 2;
            continue;
        end
        in_quotes = ~in_quotes;
    elseif ch == ',' && ~in_quotes
        row{end + 1} = current; %#ok<AGROW>
        current = '';
    else
        current(end + 1) = ch; %#ok<AGROW>
    end
    i = i + 1;
end

row{end + 1} = current;
end

function value = readScalarCounter(counter_file, default_value)
value = default_value;
if exist(counter_file, 'file') ~= 2
    return;
end

fid = fopen(counter_file, 'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid));
raw = fgetl(fid);
if ~ischar(raw)
    clear cleanup;
    return;
end

parsed = str2double(strtrim(raw));
if isfinite(parsed)
    value = parsed;
end
clear cleanup;
end

function writeScalarCounter(counter_file, value)
fid = fopen(counter_file, 'w');
if fid < 0
    error('run_band_dataset_worker:CounterWriteFailed', ...
        'Cannot write counter file: %s', counter_file);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%d\n', round(value));
clear cleanup;
end

function value = sanitizeDoneValue(value)
value = char(string(value));
value = strrep(value, sprintf('\r'), ' ');
value = strrep(value, sprintf('\n'), ' ');
end

function text = logicalText(tf)
if tf
    text = 'true';
else
    text = 'false';
end
end

function text = numericText(value)
if isnan(value)
    text = '';
else
    text = sprintf('%.6f', value);
end
end

function text = workerIdText(worker_id)
if isempty(worker_id)
    text = '';
else
    text = char(string(worker_id));
end
end

function text = csvField(value)
text = char(string(value));
text = strrep(text, '"', '""');
text = ['"', text, '"'];
end
