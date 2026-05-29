function launch = run_band_dataset_batch(config_or_overrides)
%RUN_BAND_DATASET_BATCH Launch multiple MATLAB worker processes.
%
% Example:
%   cfg = band_dataset_config_template('worker_count', 4);
%   run_band_dataset_batch(cfg);

cfg = normalizeBatchConfig(config_or_overrides);
root_dir = AddAcousticBandPaths();

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

selection = ResolveTensorTaskSelection(cfg);
manifest_file = fullfile(cfg.output_dir, 'task_manifest.csv');
writeTaskManifest(manifest_file, selection);
printTaskSelectionSummary(selection, manifest_file);

cfg.tensor_files = selection.selected_files;
cfg.task_index_start_requested = selection.requested_start;
cfg.task_index_end_requested = selection.requested_end;
cfg.task_index_start = [];
cfg.task_index_end = [];
cfg.task_selection_source = selection.source;
cfg.task_total_count = selection.total_count;
cfg.task_selected_count = selection.selected_count;
cfg.task_index_start_effective = selection.effective_start;
cfg.task_index_end_effective = selection.effective_end;
cfg.task_manifest_file = manifest_file;

config_file = fullfile(cfg.output_dir, 'batch_config.mat');
save(config_file, 'cfg', '-v7');

launch = struct();
launch.config_file = config_file;
launch.worker_count = cfg.worker_count;
launch.commands = cell(cfg.worker_count, 1);
launch.log_files = cell(cfg.worker_count, 1);
launch.launch_files = cell(cfg.worker_count, 1);
launch.task_manifest_file = manifest_file;
launch.task_total_count = selection.total_count;
launch.task_selected_count = selection.selected_count;
launch.task_index_start_effective = selection.effective_start;
launch.task_index_end_effective = selection.effective_end;
launch.first_case_id = '';
launch.last_case_id = '';
if selection.selected_count > 0
    launch.first_case_id = selection.selected_case_ids{1};
    launch.last_case_id = selection.selected_case_ids{end};
end

matlab_bin = resolveMatlabBinary(cfg);
module_dir = fullfile(root_dir, 'acoustic_band_comsol');
worker_script = buildWorkerScript(config_file, module_dir);

for i = 1:cfg.worker_count
    log_file = fullfile(cfg.output_dir, sprintf('worker_%02d.log', i));
    launch_file = buildLaunchFile(cfg.output_dir, i);
    writeLaunchFile(launch_file, matlab_bin, worker_script, log_file);
    cmd = buildLaunchCommand(launch_file);
    launch.commands{i} = cmd;
    launch.log_files{i} = log_file;
    launch.launch_files{i} = launch_file;
    [status, out] = system(cmd);
    if status ~= 0
        warning('run_band_dataset_batch:WorkerLaunchFailed', ...
            'Worker %d launch returned status %d: %s', i, status, strtrim(out));
    end
end
end

function worker_script = buildWorkerScript(config_file, module_dir)
worker_script = ['try, addpath(''', matlabEscape(module_dir), ...
    '''); AddAcousticBandPaths(); run_band_dataset_worker(''', ...
    matlabEscape(config_file), ...
    '''); catch ME, disp(getReport(ME,''extended'')); exit(1); end; exit(0);'];
end

function out = matlabEscape(path_str)
out = strrep(path_str, '''', '''''');
end

function cfg = normalizeBatchConfig(config_or_overrides)
if nargin < 1 || isempty(config_or_overrides)
    cfg = band_dataset_config_template();
elseif isstruct(config_or_overrides)
    cfg = band_dataset_config_template(config_or_overrides);
else
    error('run_band_dataset_batch:InvalidConfig', ...
        'Use a config struct returned by band_dataset_config_template.');
end
end

function matlab_bin = resolveMatlabBinary(cfg)
mode = 'matlab';
if isfield(cfg, 'worker_launch_mode') && ~isempty(cfg.worker_launch_mode)
    mode = char(string(cfg.worker_launch_mode));
end
if ~strcmpi(mode, 'matlab')
    error('run_band_dataset_batch:UnsupportedWorkerLaunchMode', ...
        ['Only cfg.worker_launch_mode = ''matlab'' is supported in the ', ...
        'manual COMSOL-with-MATLAB workflow. Worker LiveLink startup now ', ...
        'happens inside run_band_dataset_worker.']);
end
if isfield(cfg, 'worker_matlab_bin') && ~isempty(cfg.worker_matlab_bin)
    matlab_bin = shellQuote(cfg.worker_matlab_bin);
else
    matlab_bin = shellQuote('matlab');
end
end

function out = shellQuote(text)
text = char(string(text));
out = ['"', strrep(text, '"', '""'), '"'];
end

function launch_file = buildLaunchFile(output_dir, worker_index)
if ispc
    launch_file = fullfile(output_dir, sprintf('launch_worker_%02d.bat', worker_index));
else
    launch_file = fullfile(output_dir, sprintf('launch_worker_%02d.sh', worker_index));
end
end

function writeLaunchFile(launch_file, matlab_bin, worker_script, log_file)
fid = fopen(launch_file, 'w');
if fid < 0
    error('run_band_dataset_batch:CannotWriteLaunchFile', ...
        'Cannot write worker launch file: %s', launch_file);
end
cleanup = onCleanup(@() fclose(fid));

if ispc
    fprintf(fid, '@echo off\r\n');
    fprintf(fid, '%s -batch "%s" > "%s" 2>&1\r\n', ...
        matlab_bin, worker_script, log_file);
else
    fprintf(fid, '#!/usr/bin/env bash\n');
    fprintf(fid, '%s -batch "%s" > "%s" 2>&1\n', ...
        matlab_bin, worker_script, log_file);
end
clear cleanup;

if ~ispc
    fileattrib(launch_file, '+x', 'a');
end
end

function cmd = buildLaunchCommand(launch_file)
if ispc
    cmd = sprintf('start /B "" "%s"', launch_file);
else
    cmd = sprintf('nohup "%s" > /dev/null 2>&1 &', launch_file);
end
end

function writeTaskManifest(manifest_file, selection)
fid = fopen(manifest_file, 'w');
if fid < 0
    error('run_band_dataset_batch:CannotWriteTaskManifest', ...
        'Cannot write task manifest: %s', manifest_file);
end
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, 'task_index,case_id,tensor_file\n');
for i = 1:selection.selected_count
    task_index = selection.effective_start + i - 1;
    fprintf(fid, '%s,%s,%s\n', ...
        csvField(task_index), ...
        csvField(selection.selected_case_ids{i}), ...
        csvField(selection.selected_files{i}));
end
clear cleanup;
end

function printTaskSelectionSummary(selection, manifest_file)
fprintf('Task selection:\n');
fprintf('  source: %s\n', selection.source);
fprintf('  total_discovered_tasks: %d\n', selection.total_count);
fprintf('  requested_range: %s\n', describeRequestedRange(selection));
fprintf('  effective_range: %s\n', describeEffectiveRange(selection));
fprintf('  selected_task_count: %d\n', selection.selected_count);
if selection.selected_count > 0
    fprintf('  first_case_id: %s\n', selection.selected_case_ids{1});
    fprintf('  last_case_id: %s\n', selection.selected_case_ids{end});
else
    fprintf('  first_case_id: <none>\n');
    fprintf('  last_case_id: <none>\n');
end
if selection.end_clamped
    fprintf('  range_end_clamped_to_task_count: true\n');
end
fprintf('  task_manifest: %s\n', manifest_file);
end

function text = describeRequestedRange(selection)
if isempty(selection.requested_start) && isempty(selection.requested_end)
    text = '<all>';
    return;
end

start_index = selection.requested_start;
end_index = selection.requested_end;
if isempty(start_index)
    start_index = 1;
end
if isempty(end_index)
    text = sprintf('%d..end', start_index);
else
    text = sprintf('%d..%d', start_index, end_index);
end
end

function text = describeEffectiveRange(selection)
if isempty(selection.effective_start)
    text = '<empty>';
else
    text = sprintf('%d..%d', selection.effective_start, selection.effective_end);
end
end

function text = csvField(value)
text = char(string(value));
text = strrep(text, '"', '""');
text = ['"', text, '"'];
end
