function boundaries = ExtractBoundaryPolygons(geom, cfg)
%EXTRACTBOUNDARYPOLYGONS Extract display-aligned solid/void boundaries.
%
% This function is intentionally independent from COMSOL. It provides an
% inspectable boundary artifact for validation and downstream data pipelines.

if nargin < 2 || isempty(cfg)
    cfg = geom.config;
end

L = cfg.unit_cell_length;
Z = double(geom.solidMaskDisplay);
[ny, nx] = size(Z);
x = linspace(0, L, nx);
y = linspace(0, L, ny);
C = contourc(x, y, Z, [0.5, 0.5]);

items = {};
k = 1;
while k < size(C, 2)
    level = C(1, k);
    npt = C(2, k);
    pts = C(:, k + 1:k + npt).';
    k = k + npt + 1;

    if isempty(pts)
        continue;
    end
    pts = simplifyPolyline(pts, cfg.geometry_mindist_pixels * L / max(nx, ny));

    closed = norm(pts(1, :) - pts(end, :)) < (2 * L / max(nx, ny));
    item = struct();
    item.level = level;
    item.xy = pts;
    item.closed = closed;
    item.area = signedPolygonArea(pts);
    item.num_points = size(pts, 1);
    items{end + 1} = item; %#ok<AGROW>
end

boundaries = struct();
boundaries.coordinate_frame = 'display_aligned_unit_cell';
boundaries.note = ['solidMaskDisplay = flipud(xPhysCanonical >= threshold); ', ...
    'this matches the black material silhouette in saved PNG images.'];
boundaries.unit_cell_length = L;
boundaries.items = [items{:}];
boundaries.num_boundaries = numel(items);

end

function out = simplifyPolyline(pts, min_dist)
if size(pts, 1) <= 2 || min_dist <= 0
    out = pts;
    return;
end
keep = true(size(pts, 1), 1);
last = pts(1, :);
for i = 2:size(pts, 1) - 1
    if norm(pts(i, :) - last) < min_dist
        keep(i) = false;
    else
        last = pts(i, :);
    end
end
out = pts(keep, :);
end

function area = signedPolygonArea(pts)
if size(pts, 1) < 3
    area = 0;
    return;
end
x = pts(:, 1);
y = pts(:, 2);
area = 0.5 * sum(x .* y([2:end, 1]) - y .* x([2:end, 1]));
end
