function bz = GetBrillouinZonePath(symmetry_group, unit_cell_length, cfg)
%GETBRILLOUINZONEPATH Select a high-symmetry BZ path from wallpaper group.

if nargin < 3 || isempty(cfg)
    cfg = AcousticBandConfig('unit_cell_length', unit_cell_length);
end
AddAcousticBandPaths();

[sg_name, phi_degrees] = GetSpaceGroupConfig(symmetry_group);
L = unit_cell_length;
phi = deg2rad(phi_degrees);

a1 = L * [1, 0];
a2 = L * [cos(phi), sin(phi)];
A = [a1(:), a2(:)];
B = 2 * pi * inv(A).';
b1 = B(:, 1).';
b2 = B(:, 2).';

if ismember(sg_name, {'p3', 'p3m1', 'p31m', 'p6', 'p6mm'})
    labels = {'G', 'M', 'K', 'G'};
    points = [0, 0; (b1 + b2) / 2; (2 * b1 + b2) / 3; 0, 0];
elseif ismember(sg_name, {'p4', 'p4mm', 'p4gm'})
    labels = {'G', 'X', 'M', 'G'};
    points = [0, 0; b1 / 2; (b1 + b2) / 2; 0, 0];
else
    labels = {'G', 'X', 'M', 'Y', 'G'};
    points = [0, 0; b1 / 2; (b1 + b2) / 2; b2 / 2; 0, 0];
end

[k_points, path_s, tick_s, point_labels] = interpolatePath(points, labels, ...
    cfg.path_points_per_segment);

bz = struct();
bz.symmetry_group = sg_name;
bz.phi_degrees = phi_degrees;
bz.unit_cell_length = L;
bz.direct_basis = [a1; a2];
bz.reciprocal_basis = [b1; b2];
bz.high_symmetry_labels = labels;
bz.high_symmetry_points = points;
bz.k_points = k_points;
bz.path_coordinate = path_s;
bz.tick_coordinate = tick_s;
bz.point_labels = point_labels;
bz.path_name = strjoin(labels, '-');

end

function [klist, s, ticks, point_labels] = interpolatePath(points, labels, nseg)
klist = [];
s = [];
ticks = zeros(size(points, 1), 1);
point_labels = {};
dist_acc = 0;

for i = 1:size(points, 1) - 1
    p0 = points(i, :);
    p1 = points(i + 1, :);
    tvals_full = linspace(0, 1, nseg + 1);
    seg_full = p0 + (p1 - p0) .* tvals_full(:);
    s_full = [0; cumsum(vecnorm(diff(seg_full, 1, 1), 2, 2))];
    if isempty(klist)
        klist = seg_full;
        s = dist_acc + s_full;
        point_labels = labels(1);
    else
        klist = [klist; seg_full(2:end, :)]; %#ok<AGROW>
        s = [s; dist_acc + s_full(2:end)]; %#ok<AGROW>
    end
    dist_acc = s(end);
    ticks(i + 1) = dist_acc;
    point_labels{end + 1} = labels{i + 1}; %#ok<AGROW>
end
end
