function ConfigureComsolKPathSweep(model, bz, cfg)
%CONFIGURECOMSOLKPATHSWEEP Store the BZ path as one internal COMSOL sweep.
%
% The sweep uses one dimensionless parameter, ik, so COMSOL follows the
% prescribed k-path order instead of expanding kx and ky as a full grid.

if nargin < 3 || isempty(cfg)
    cfg = AcousticBandConfig();
end

k_points = bz.k_points;
n_k = size(k_points, 1);
if n_k < 1 || size(k_points, 2) ~= 2
    error('ConfigureComsolKPathSweep:InvalidKPoints', ...
        'bz.k_points must be an N x 2 matrix.');
end

model.param.set('ik', '1');
model.param.set('num_k_path_points', num2str(n_k));
model.param.set('kx', 'kx_path(ik)[1/m]');
model.param.set('ky', 'ky_path(ik)[1/m]');

createPathInterpolation(model, 'kx_path_fun', 'kx_path', k_points(:, 1), ...
    'Bloch kx along path');
createPathInterpolation(model, 'ky_path_fun', 'ky_path', k_points(:, 2), ...
    'Bloch ky along path');

study = model.study('std1');
removeStudyFeatureIfPresent(study, 'param');
param = study.feature.create('param', 'Parametric');
moveStudyFeatureIfPossible(study, 'param', 0);
param.label('Internal k-path sweep');
plist = sprintf('range(1,1,%d)', n_k);
setPropertyIfPossible(param, {'pname'}, {'ik'});
setPropertyIfPossible(param, {'plistarr'}, {plist});
setPropertyIfPossible(param, {'punit'}, {''});
setPropertyIfPossible(param, {'sweeptype'}, 'sparse');
setPropertyIfPossible(param, {'paramselect'}, 'off');
if ~setPropertyIfPossible(param, {'keepsol'}, 'all')
    setPropertyIfPossible(param, {'keepsol'}, 'on');
end
setPropertyIfPossible(param, {'keepplistsol', 'storeparamsol'}, 'all');
setPropertyIfPossible(param, {'plot'}, 'off');

% This setIndex form follows the LiveLink documentation for Parametric
% Sweep study steps and is required by some COMSOL versions.
setIndexIfPossible(param, 'pname', 'ik', 0);
setIndexIfPossible(param, 'plistarr', plist, 0);
setIndexIfPossible(param, 'punit', '', 0);

if isfield(cfg, 'verbose') && cfg.verbose
    fprintf('Configured COMSOL Parametric Sweep: ik = 1:%d\n', n_k);
end

end

function createPathInterpolation(model, tag, funcname, values, label_text)
removeFunctionIfPresent(model, tag);

fn = model.func.create(tag, 'Interpolation');
fn.label(label_text);
setPropertyIfPossible(fn, {'funcname'}, funcname);
setPropertyIfPossible(fn, {'source'}, 'table');
setPropertyIfPossible(fn, {'nargs'}, '1');
setPropertyIfPossible(fn, {'interp'}, 'linear');
setPropertyIfPossible(fn, {'extrap'}, 'const');
setPropertyIfPossible(fn, {'argunit'}, '1');
setPropertyIfPossible(fn, {'fununit'}, '1');

rows = cell(numel(values), 2);
for i = 1:numel(values)
    rows{i, 1} = sprintf('%d', i);
    rows{i, 2} = sprintf('%.16g', values(i));
end
setPropertyIfPossible(fn, {'table'}, rows);
end

function removeFunctionIfPresent(model, tag)
try
    model.func.remove(tag);
catch
end
end

function removeStudyFeatureIfPresent(study, tag)
try
    study.feature.remove(tag);
catch
end
end

function ok = moveStudyFeatureIfPossible(study, tag, index)
ok = false;
try
    study.feature.move(tag, index);
    ok = true;
catch
end
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

function ok = setIndexIfPossible(obj, name, value, index)
ok = false;
try
    obj.setIndex(name, value, index);
    ok = true;
catch
end
end
