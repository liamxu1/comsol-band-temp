function [model, periodic_pairs] = BuildComsolAcousticBandModel(geom, cfg)
%BUILDCOMSOLACOUSTICBANDMODEL Create pressure-acoustics Bloch eigenmodel.
%
% Physics assumption: the B-spline solid phase is acoustically rigid; the
% pressure-acoustics Helmholtz eigenproblem is solved in the void/fluid
% domain. Unit-cell exterior boundaries are paired with Floquet/Bloch
% periodic conditions. Internal solid boundaries keep the acoustic hard-wall
% default unless the user changes the model after construction.

if nargin < 2 || isempty(cfg)
    cfg = geom.config;
end

import com.comsol.model.*
import com.comsol.model.util.*

model = ModelUtil.create(['acoustic_band_', sanitizeTag(cfg.case_id)]);
model.modelPath(cfg.output_dir);
model.label([cfg.case_id, '_acoustic_band.mph']);

model.param.set('a', sprintf('%.16g[m]', cfg.unit_cell_length));
model.param.set('c0', sprintf('%.16g[m/s]', cfg.sound_speed));
model.param.set('rho0', sprintf('%.16g[kg/m^3]', cfg.density));
model.param.set('kx', '0[1/m]');
model.param.set('ky', '0[1/m]');
model.param.set('hmax', sprintf('%.16g[m]', cfg.unit_cell_length * cfg.mesh_max_size_fraction));
model.param.set('hmin', sprintf('%.16g[m]', cfg.unit_cell_length * cfg.mesh_min_size_fraction));

comp = model.component.create('comp1', true);
geom1 = comp.geom.create('geom1', 2);
geom1.lengthUnit('m');

BuildImageGeometry(model, geom, cfg);
geom1.run;

mat = comp.material.create('mat1', 'Common');
mat.selection.all;
mat.propertyGroup('def').set('density', 'rho0');
setPropertyIfPossible(mat.propertyGroup('def'), {'soundspeed', 'speedofsound', 'c'}, 'c0');

physics = comp.physics.create('acpr', 'PressureAcoustics', 'geom1');
physics.selection.all;
fpam = physics.feature('fpam1');
fpam.set('rho_mat', 'userdef');
fpam.set('rho', 'rho0');
fpam.set('c_mat', 'userdef');
fpam.set('c', 'c0');

periodic_pairs = CreateBlochPeriodicConditions(model, physics, cfg);

mesh = comp.mesh.create('mesh1');
mesh.feature.create('ftri1', 'FreeTri');
mesh.feature.create('size1', 'Size');
mesh.feature('size1').set('custom', 'on');
mesh.feature('size1').set('hmax', 'hmax');
mesh.feature('size1').set('hmin', 'hmin');
mesh.run;

study = model.study.create('std1');
study.feature.create('eig', 'Eigenfrequency');
study.feature('eig').set('neigsactive', 'on');
study.feature('eig').set('neigs', num2str(cfg.num_eigenfrequencies));
study.feature('eig').set('shiftactive', 'on');
study.feature('eig').set('useeigunit', 'on');
study.feature('eig').set('eigunit', 'Hz');
study.feature('eig').set('shift', sprintf('%.16g', cfg.search_frequency));
study.feature('eig').set('eigwhich', 'lm');

end

function BuildImageGeometry(model, geom, cfg)
if isfield(geom, 'comsol_geometry_type') && ...
        strcmp(char(geom.comsol_geometry_type), 'circular_inclusion')
    BuildCircularInclusionGeometry(model, geom);
    return;
end

image_data = double(geom.voidMaskForComsol);
scale = imageToGeometryScale(size(image_data), cfg.unit_cell_length);
minarea = cfg.geometry_minarea_fraction * numel(image_data);
geomnode = model.component('comp1').geom('geom1');

if all(image_data(:) > cfg.threshold)
    rect = geomnode.feature.create('void_rect', 'Rectangle');
    rect.set('pos', {'0', '0'});
    rect.set('size', {'a', 'a'});
    return;
elseif all(image_data(:) <= cfg.threshold)
    error('BuildComsolAcousticBandModel:NoFluidDomain', ...
        'The selected acoustic phase is empty; no pressure-acoustics domain can be built.');
end

function BuildCircularInclusionGeometry(model, geom)
geomnode = model.component('comp1').geom('geom1');
radius = geom.inclusion_radius;
model.param.set('inclusion_radius', sprintf('%.16g[m]', radius));

rect = geomnode.feature.create('void_rect', 'Rectangle');
rect.set('pos', {'0', '0'});
rect.set('size', {'a', 'a'});

circle = geomnode.feature.create('rigid_circle', 'Circle');
circle.set('pos', {'0.5*a', '0.5*a'});
circle.set('r', 'inclusion_radius');

fluid = geomnode.feature.create('fluid_domain', 'Difference');
fluid.selection('input').set({'void_rect'});
fluid.selection('input2').set({'rigid_circle'});
end

try
    mphimage2geom(image_data, cfg.threshold, ...
        'geom', geomnode, ...
        'type', 'solid', ...
        'curvetype', cfg.geometry_curve_type, ...
        'scale', scale, ...
        'mindist', cfg.geometry_mindist_pixels, ...
        'minarea', minarea);
catch ME
    if shouldUseExteriorFluidFallback(image_data, cfg)
        try
            resetGeneratedImageFeatures(geomnode);
            buildExteriorFluidGeometry(geomnode, image_data, scale, minarea, cfg);
            return;
        catch ME2
            error('BuildComsolAcousticBandModel:ImageToGeomFailed', ...
                ['mphimage2geom failed, and the exterior-fluid fallback also failed. ', ...
                'Original error: %s | Fallback error: %s'], ...
                ME.message, ME2.message);
        end
    end
    error('BuildComsolAcousticBandModel:ImageToGeomFailed', ...
        ['mphimage2geom failed. Check that COMSOL LiveLink is loaded and ', ...
        'that the image-to-geometry function is available. Original error: %s'], ...
        ME.message);
end
end

function tf = shouldUseExteriorFluidFallback(image_data, cfg)
tf = false;
if ~(isfield(cfg, 'solid_phase_value') && isequal(cfg.solid_phase_value, 0))
    return;
end

mask = image_data > cfg.threshold;
if ~touchesAllOuterSides(mask)
    return;
end

void_mask = ~mask;
if touchesAnyOuterSide(void_mask)
    return;
end

tf = true;
end

function tf = touchesAllOuterSides(mask)
tf = any(mask(:, 1)) && any(mask(:, end)) && any(mask(1, :)) && any(mask(end, :));
end

function tf = touchesAnyOuterSide(mask)
tf = any(mask(:, 1)) || any(mask(:, end)) || any(mask(1, :)) || any(mask(end, :));
end

function buildExteriorFluidGeometry(geomnode, image_data, scale, minarea, cfg)
mask = image_data > cfg.threshold;
solid_islands = ~mask;
if ~any(solid_islands(:))
    rect = geomnode.feature.create('void_rect', 'Rectangle');
    rect.set('pos', {'0', '0'});
    rect.set('size', {'a', 'a'});
    return;
end

rect = geomnode.feature.create('void_rect', 'Rectangle');
rect.set('pos', {'0', '0'});
rect.set('size', {'a', 'a'});

try
    mphimage2geom(double(solid_islands), cfg.threshold, ...
        'geom', geomnode, ...
        'type', 'solid', ...
        'curvetype', cfg.geometry_curve_type, ...
        'scale', scale, ...
        'mindist', cfg.geometry_mindist_pixels, ...
        'minarea', minarea);
catch ME
    error('Exterior fluid fallback could not build interior solid islands: %s', ...
        ME.message);
end

feature_tags = cell(geomnode.feature.tags());
curve_tags = feature_tags(startsWith(feature_tags, 'curve'));
if isempty(curve_tags)
    error('Exterior fluid fallback found no curve features to subtract.');
end

diff_tag = 'fluid_domain';
if any(strcmp(feature_tags, diff_tag))
    geomnode.feature.remove(diff_tag);
end
fluid = geomnode.feature.create(diff_tag, 'Difference');
fluid.selection('input').set({'void_rect'});
fluid.selection('input2').set(curve_tags);
end

function resetGeneratedImageFeatures(geomnode)
tags = cell(geomnode.feature.tags());
for i = 1:numel(tags)
    tag = tags{i};
    if startsWith(tag, 'curve') || strcmp(tag, 'void_rect') || strcmp(tag, 'fluid_domain')
        try
            geomnode.feature.remove(tag);
        catch
        end
    end
end
end

function scale = imageToGeometryScale(image_size, unit_cell_length)
% mphimage2geom places image samples on a coordinate grid. Using L/N leaves
% the last row/column at L - dx, so x=L and y=L boundary selections miss.
n = max(image_size);
if n <= 1
    scale = unit_cell_length;
else
    scale = unit_cell_length / (n - 1);
end
end

function periodic_pairs = CreateBlochPeriodicConditions(model, physics, cfg)
tol = cfg.unit_cell_length * 1e-5;
L = cfg.unit_cell_length;

left = selectBoundaries(model, [-tol, tol; -tol, L + tol]);
right = selectBoundaries(model, [L - tol, L + tol; -tol, L + tol]);
bottom = selectBoundaries(model, [-tol, L + tol; -tol, tol]);
top = selectBoundaries(model, [-tol, L + tol; L - tol, L + tol]);

periodic_pairs = struct();
periodic_pairs.left_boundary_ids = left(:).';
periodic_pairs.right_boundary_ids = right(:).';
periodic_pairs.bottom_boundary_ids = bottom(:).';
periodic_pairs.top_boundary_ids = top(:).';
periodic_pairs.left_boundary_count = numel(left);
periodic_pairs.right_boundary_count = numel(right);
periodic_pairs.bottom_boundary_count = numel(bottom);
periodic_pairs.top_boundary_count = numel(top);
periodic_pairs.periodic_x = createPeriodicPairIfPresent(physics, 'pcx', left, right);
periodic_pairs.periodic_y = createPeriodicPairIfPresent(physics, 'pcy', bottom, top);
periodic_pairs.is_strict_bloch_valid = ...
    periodic_pairs.periodic_x && periodic_pairs.periodic_y;
end

function created = createPeriodicPairIfPresent(physics, tag, side_a, side_b)
created = false;
if isempty(side_a) && isempty(side_b)
    warning('BuildComsolAcousticBandModel:SkippedPeriodicPair', ...
        'Skipping %s because both paired boundary selections are empty.', tag);
    return;
end
if isempty(side_a) || isempty(side_b)
    warning('BuildComsolAcousticBandModel:SkippedPeriodicPair', ...
        ['Skipping %s because one paired boundary selection is empty. ', ...
        'This happens when the acoustic/fluid phase does not touch both ', ...
        'opposite unit-cell sides.'], tag);
    return;
end

pc = physics.feature.create(tag, 'PeriodicCondition', 1);
pc.selection.set(unique([side_a(:); side_b(:)]));
setBlochProperties(pc);
created = true;
end

function ids = selectBoundaries(model, box)
try
    ids = mphselectbox(model, 'geom1', box, 'boundary');
catch
    ids = [];
end
if isempty(ids)
    warning('BuildComsolAcousticBandModel:EmptyBoundarySelection', ...
        'A periodic boundary selection is empty for box %s.', mat2str(box));
end
end

function setBlochProperties(feature)
% COMSOL property names vary slightly by version/interface. Try the common
% names and keep the feature visible if one property spelling is rejected.
setPropertyIfPossible(feature, {'PeriodicType', 'periodicType', 'type'}, 'Floquet');
setPropertyIfPossible(feature, {'kFloquet'}, {'kx', 'ky', '0'});
setPropertyIfPossible(feature, {'kF', 'waveVector'}, {'kx', 'ky'});
setPropertyIfPossible(feature, {'FloquetPeriodic', 'floquet'}, 'on');
end

function ok = setPropertyIfPossible(obj, names, value)
ok = false;
for i = 1:numel(names)
    try
        obj.set(names{i}, value);
        ok = true;
        return;
    catch
    end
end
end

function tag = sanitizeTag(s)
if isempty(s)
    s = 'case';
end
tag = regexprep(char(s), '[^A-Za-z0-9_]', '_');
if isempty(regexp(tag(1), '[A-Za-z]', 'once'))
    tag = ['m_', tag];
end
end
