function launch = run_band_dataset_batch(config_or_overrides)
%RUN_BAND_DATASET_BATCH Launch multiple MATLAB worker processes.
%
% Example:
%   cfg = band_dataset_config_template('worker_count', 4);
%   run_band_dataset_batch(cfg);

cfg = normalizeBatchConfig(config_or_overrides);
AddAcousticBandPaths();

if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

config_file = fullfile(cfg.output_dir, 'batch_config.mat');
save(config_file, 'cfg', '-v7');

launch = struct();
launch.config_file = config_file;
launch.worker_count = cfg.worker_count;
launch.commands = cell(cfg.worker_count, 1);
launch.log_files = cell(cfg.worker_count, 1);
launch.launch_files = cell(cfg.worker_count, 1);

matlab_bin = resolveMatlabBinary();
worker_script = ['try, run_band_dataset_worker(''', config_file, ...
    '''); catch ME, disp(getReport(ME,''extended'')); exit(1); end; exit(0);'];

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

function matlab_bin = resolveMatlabBinary()
matlab_bin = 'matlab';
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
    fprintf(fid, '"%s" -batch "%s" > "%s" 2>&1\r\n', ...
        matlab_bin, worker_script, log_file);
else
    fprintf(fid, '#!/usr/bin/env bash\n');
    fprintf(fid, '"%s" -batch "%s" > "%s" 2>&1\n', ...
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
