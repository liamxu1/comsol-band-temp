function selection = ResolveTensorTaskSelection(cfg)
%RESOLVETENSORTASKSELECTION Resolve deterministic task ordering and slicing.

[all_files, source] = resolveSourceFiles(cfg);
total = numel(all_files);
[requested_start, requested_end] = resolveRequestedRange(cfg);
[effective_start, effective_end, end_clamped] = resolveEffectiveRange( ...
    requested_start, requested_end, total);

if isempty(effective_start)
    selected_files = cell(0, 1);
else
    selected_files = all_files(effective_start:effective_end);
end

selected_case_ids = buildCaseIds(selected_files, cfg);

selection = struct();
selection.source = source;
selection.all_files = all_files;
selection.selected_files = selected_files;
selection.selected_case_ids = selected_case_ids;
selection.total_count = total;
selection.selected_count = numel(selected_files);
selection.requested_start = requested_start;
selection.requested_end = requested_end;
selection.effective_start = effective_start;
selection.effective_end = effective_end;
selection.end_clamped = end_clamped;
end

function [files, source] = resolveSourceFiles(cfg)
if isfield(cfg, 'tensor_files') && ~isempty(cfg.tensor_files)
    files = normalizeFileList(cfg.tensor_files);
    source = 'tensor_files';
    return;
end

listing = dir(fullfile(cfg.tensor_dir, '*_tensor.mat'));
[~, order] = sort({listing.name});
listing = listing(order);
files = cellfun(@(f, n) fullfile(f, n), {listing.folder}, {listing.name}, ...
    'UniformOutput', false);
files = files(:);
source = 'tensor_dir';
end

function files = normalizeFileList(raw_files)
if ischar(raw_files) || (isstring(raw_files) && isscalar(raw_files))
    files = {char(string(raw_files))};
elseif isstring(raw_files)
    files = cellstr(raw_files(:));
elseif iscell(raw_files)
    files = cellstr(string(raw_files(:)));
else
    error('ResolveTensorTaskSelection:InvalidTensorFiles', ...
        'cfg.tensor_files must be a char vector, string array, or cell array.');
end
files = files(:);
end

function [start_index, end_index] = resolveRequestedRange(cfg)
start_index = readOptionalPositiveInteger(cfg, 'task_index_start');
end_index = readOptionalPositiveInteger(cfg, 'task_index_end');
end

function value = readOptionalPositiveInteger(cfg, field_name)
value = [];
if ~isfield(cfg, field_name) || isempty(cfg.(field_name))
    return;
end

raw = double(cfg.(field_name));
if ~isscalar(raw) || ~isfinite(raw) || raw < 1 || raw ~= floor(raw)
    error('ResolveTensorTaskSelection:InvalidRange', ...
        '%s must be a positive integer scalar.', field_name);
end
value = raw;
end

function [start_index, end_index, end_clamped] = resolveEffectiveRange( ...
        requested_start, requested_end, total_count)
end_clamped = false;

if isempty(requested_start) && isempty(requested_end)
    if total_count == 0
        start_index = [];
        end_index = [];
    else
        start_index = 1;
        end_index = total_count;
    end
    return;
end

if total_count == 0
    error('ResolveTensorTaskSelection:NoTasksInRange', ...
        'No tasks were discovered, but a task index range was requested.');
end

if isempty(requested_start)
    start_index = 1;
else
    start_index = requested_start;
end

if isempty(requested_end)
    end_index = total_count;
else
    end_index = requested_end;
end

if start_index > total_count
    error('ResolveTensorTaskSelection:RangeStartOutOfBounds', ...
        'task_index_start (%d) exceeds the discovered task count (%d).', ...
        start_index, total_count);
end

if end_index < start_index
    error('ResolveTensorTaskSelection:InvalidRangeOrder', ...
        'task_index_end (%d) must be greater than or equal to task_index_start (%d).', ...
        end_index, start_index);
end

if end_index > total_count
    end_index = total_count;
    end_clamped = true;
end
end

function case_ids = buildCaseIds(files, cfg)
case_ids = cell(size(files));
for i = 1:numel(files)
    [~, base] = fileparts(files{i});
    case_id = regexprep(base, '_tensor$', '');
    if isfield(cfg, 'case_name_suffix') && ~isempty(cfg.case_name_suffix)
        case_id = [case_id, cfg.case_name_suffix];
    end
    case_ids{i} = case_id;
end
end
