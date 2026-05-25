function bz = InterpolateBrillouinZonePath(high_symmetry_points, labels, total_k_points, metadata)
%INTERPOLATEBRILLOUINZONEPATH Build a fixed-size k-path through key points.
%
% total_k_points counts all points on the concatenated path, including the
% repeated endpoint at the end of the final segment.

if isstruct(high_symmetry_points)
    if nargin < 2
        labels = [];
    end
    if nargin < 3
        total_k_points = [];
    end
    if nargin < 4
        metadata = struct();
    end
    [high_symmetry_points, labels, total_k_points, metadata] = ...
        unpackBasePathStruct(high_symmetry_points, labels, total_k_points, metadata);
elseif nargin < 4
    metadata = struct();
end

if size(high_symmetry_points, 1) ~= numel(labels)
    error('InterpolateBrillouinZonePath:SizeMismatch', ...
        'The number of high-symmetry points must match the number of labels.');
end
if total_k_points < numel(labels)
    error('InterpolateBrillouinZonePath:TooFewPoints', ...
        'total_k_points must be at least the number of high-symmetry labels.');
end

num_segments = size(high_symmetry_points, 1) - 1;
segment_vectors = diff(high_symmetry_points, 1, 1);
segment_lengths = vecnorm(segment_vectors, 2, 2);

interval_total = total_k_points - 1;
interval_counts = allocateIntervals(segment_lengths, interval_total);
[k_points, path_s, tick_s, point_labels] = interpolateCustomPath( ...
    high_symmetry_points, labels, interval_counts);

bz = metadata;
bz.high_symmetry_labels = labels;
bz.high_symmetry_points = high_symmetry_points;
bz.k_points = k_points;
bz.path_coordinate = path_s;
bz.tick_coordinate = tick_s;
bz.point_labels = point_labels;
bz.path_name = strjoin(labels, '-');
end

function [points, labels, total_k_points, metadata] = unpackBasePathStruct(base_bz, labels, total_k_points, metadata)
if nargin < 4
    metadata = struct();
end

if nargin < 3 || isempty(total_k_points)
    total_k_points = labels;
end
if nargin < 2 || isempty(labels) || isscalar(labels)
    labels = base_bz.high_symmetry_labels;
end

points = base_bz.high_symmetry_points;
base_fields = {'symmetry_group', 'phi_degrees', 'unit_cell_length', ...
    'direct_basis', 'reciprocal_basis'};
base_metadata = struct();
for i = 1:numel(base_fields)
    field_name = base_fields{i};
    if isfield(base_bz, field_name)
        base_metadata.(field_name) = base_bz.(field_name);
    end
end
metadata = mergeStruct(base_metadata, metadata);
end

function interval_counts = allocateIntervals(segment_lengths, interval_total)
num_segments = numel(segment_lengths);
interval_counts = ones(num_segments, 1);
remaining = interval_total - num_segments;
if remaining < 0
    error('InterpolateBrillouinZonePath:TooFewIntervals', ...
        'Not enough intervals to cover each k-path segment.');
end
if remaining == 0
    return;
end

total_length = sum(segment_lengths);
if total_length <= 0
    raw_extra = ones(num_segments, 1) * (remaining / num_segments);
else
    raw_extra = remaining * (segment_lengths / total_length);
end

extra_floor = floor(raw_extra);
interval_counts = interval_counts + extra_floor;
leftover = remaining - sum(extra_floor);

if leftover > 0
    [~, order] = sort(raw_extra - extra_floor, 'descend');
    interval_counts(order(1:leftover)) = interval_counts(order(1:leftover)) + 1;
end
end

function [klist, s, ticks, point_labels] = interpolateCustomPath(points, labels, interval_counts)
klist = [];
s = [];
ticks = zeros(size(points, 1), 1);
point_labels = labels(1);
dist_acc = 0;

for i = 1:numel(interval_counts)
    nseg = interval_counts(i);
    p0 = points(i, :);
    p1 = points(i + 1, :);
    tvals_full = linspace(0, 1, nseg + 1);
    seg_full = p0 + (p1 - p0) .* tvals_full(:);
    s_full = [0; cumsum(vecnorm(diff(seg_full, 1, 1), 2, 2))];
    if isempty(klist)
        klist = seg_full;
        s = dist_acc + s_full;
    else
        klist = [klist; seg_full(2:end, :)]; %#ok<AGROW>
        s = [s; dist_acc + s_full(2:end)]; %#ok<AGROW>
    end
    dist_acc = s(end);
    ticks(i + 1) = dist_acc;
    point_labels{end + 1} = labels{i + 1}; %#ok<AGROW>
end
end

function out = mergeStruct(out, in)
fields = fieldnames(in);
for i = 1:numel(fields)
    out.(fields{i}) = in.(fields{i});
end
end
