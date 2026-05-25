function AddComsolBandResults(model, bz, band_frequencies_hz, cfg)
%ADDCOMSOLBANDRESULTS Add inspectable band tables and plots to the MPH file.
%
% The numerical CSV written by SaveAcousticBandResult remains the preferred
% batch-processing label. These result nodes make the saved MPH self
% contained for manual inspection in COMSOL.

if nargin < 4 || isempty(cfg)
    cfg = AcousticBandConfig();
end

n_k = size(bz.k_points, 1);
if size(band_frequencies_hz, 1) ~= n_k
    error('AddComsolBandResults:SizeMismatch', ...
        'band_frequencies_hz must have one row per k-path point.');
end

ik = (1:n_k).';
data = [ik, bz.path_coordinate(:), bz.k_points, band_frequencies_hz];
headers = [{'ik', 's', 'kx_1_per_m', 'ky_1_per_m'}, ...
    arrayfun(@(i) sprintf('band_%02d_hz', i), ...
    1:size(band_frequencies_hz, 2), 'UniformOutput', false)];

addBandTable(model, data, headers);
addBandPlot(model, size(band_frequencies_hz, 2));
addModeShapePlot(model);

if isfield(cfg, 'verbose') && cfg.verbose
    fprintf('Added COMSOL result table/plots for %d k-points.\n', n_k);
end

end

function addBandTable(model, data, headers)
removeResultTableIfPresent(model, 'tbl_band');

tbl = model.result.table.create('tbl_band', 'Table');
tbl.label('Band frequencies (Hz)');

setPropertyIfPossible(tbl, {'comments'}, ...
    'Rows follow the internal ik sweep. Frequencies are in Hz.');
trySetColumnHeaders(tbl, headers);
trySetTableData(tbl, data);
end

function addBandPlot(model, num_bands)
removeResultFeatureIfPresent(model, 'pg_band');

pg = [];
try
    pg = model.result.create('pg_band', 'PlotGroup1D');
catch
    try
        pg = model.result.create('pg_band', 1);
    catch
    end
end
if isempty(pg)
    warning('AddComsolBandResults:BandPlotSkipped', ...
        'Could not create a 1D band plot group in this COMSOL version.');
    return;
end

pg.label('Band diagram');
setPropertyIfPossible(pg, {'xlabel'}, 'Path coordinate s (1/m)');
setPropertyIfPossible(pg, {'ylabel'}, 'Frequency (Hz)');
setPropertyIfPossible(pg, {'title'}, 'Acoustic band diagram');

try
    plot = pg.feature.create('tbl_band_plot', 'Table');
catch
    warning('AddComsolBandResults:BandPlotSkipped', ...
        'Could not create a table plot feature in this COMSOL version.');
    return;
end

plot.label('Band frequencies');
setPropertyIfPossible(plot, {'table'}, 'tbl_band');
setPropertyIfPossible(plot, {'xaxisdata', 'xdata'}, 's');
setPropertyIfPossible(plot, {'legend'}, 'on');

band_columns = arrayfun(@(i) sprintf('band_%02d_hz', i), ...
    1:num_bands, 'UniformOutput', false);
setPropertyIfPossible(plot, {'yaxisdata', 'ydata', 'plotcolumns'}, band_columns);
setPropertyIfPossible(plot, {'linewidth'}, '1.5');
end

function addModeShapePlot(model)
removeResultFeatureIfPresent(model, 'pg_mode');

pg = [];
try
    pg = model.result.create('pg_mode', 'PlotGroup2D');
catch
    try
        pg = model.result.create('pg_mode', 2);
    catch
    end
end
if isempty(pg)
    warning('AddComsolBandResults:ModePlotSkipped', ...
        'Could not create a 2D mode-shape plot group in this COMSOL version.');
    return;
end

pg.label('Pressure mode shape');
setPropertyIfPossible(pg, {'data'}, 'dset1');
setPropertyIfPossible(pg, {'outersolnum'}, '1');
setPropertyIfPossible(pg, {'solnum'}, '1');
setPropertyIfPossible(pg, {'title'}, 'Pressure mode shape');

try
    surf = pg.feature.create('surf_p', 'Surface');
catch
    warning('AddComsolBandResults:ModePlotSkipped', ...
        'Could not create a pressure surface plot in this COMSOL version.');
    return;
end

surf.label('Pressure');
if ~setPropertyIfPossible(surf, {'expr'}, 'real(acpr.p_t)')
    setPropertyIfPossible(surf, {'expr'}, 'real(p)');
end
setPropertyIfPossible(surf, {'descr'}, 'Pressure');
end

function removeResultTableIfPresent(model, tag)
try
    model.result.table.remove(tag);
catch
end
end

function removeResultFeatureIfPresent(model, tag)
try
    model.result.remove(tag);
catch
end
end

function trySetColumnHeaders(tbl, headers)
attempts = {@() tbl.setColumnHeaders(headers), ...
            @() tbl.set('headers', headers), ...
            @() tbl.set('columnheaders', headers)};
runFirstSuccessful(attempts, 'AddComsolBandResults:HeaderSkipped', ...
    'Could not set COMSOL table column headers.');
end

function trySetTableData(tbl, data)
attempts = {@() tbl.setTableData(data), ...
            @() tbl.set('table', data), ...
            @() tbl.set('data', data)};
ok = runFirstSuccessful(attempts, '', '');
if ~ok
    warning('AddComsolBandResults:TableDataSkipped', ...
        ['Could not write numerical band data into a COMSOL Table. ', ...
        'The internal parametric solution is still saved, and CSV export remains available.']);
end
end

function ok = runFirstSuccessful(attempts, warn_id, warn_msg)
ok = false;
for i = 1:numel(attempts)
    try
        attempts{i}();
        ok = true;
        return;
    catch
    end
end
if ~isempty(warn_id)
    warning(warn_id, warn_msg);
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
