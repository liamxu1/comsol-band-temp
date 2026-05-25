function files = PlotAcousticBandDiagram(result, cfg)
%PLOTACOUSTICBANDDIAGRAM Render a paper-style band diagram from one result.

if nargin < 2 || isempty(cfg)
    cfg = result.config;
end

if ~isfield(result, 'band_frequencies_hz') || isempty(result.band_frequencies_hz)
    files = struct();
    return;
end

bz = result.brillouin_zone;
freqs = result.band_frequencies_hz;
s = bz.path_coordinate(:);
tick_s = bz.tick_coordinate(:);
labels = normalizeLabels(bz.point_labels);

case_id = cfg.case_id;
png_file = fullfile(cfg.output_dir, [case_id, '_band_diagram.png']);
svg_file = fullfile(cfg.output_dir, [case_id, '_band_diagram.svg']);
meta_file = fullfile(cfg.output_dir, [case_id, '_band_diagram_meta.json']);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80, 80, 1120, 720]);
cleanup = onCleanup(@() closeFigure(fig));
ax = axes(fig); %#ok<LAXES>
hold(ax, 'on');
ax.Color = 'w';
ax.Box = 'on';
ax.LineWidth = 1.0;
ax.FontName = 'Times New Roman';
ax.FontSize = 14;
ax.XColor = [0.15, 0.15, 0.15];
ax.YColor = [0.15, 0.15, 0.15];
ax.GridAlpha = 0.08;

band_colors = lines(size(freqs, 2));
for i = 1:size(freqs, 2)
    plot(ax, s, freqs(:, i), 'LineWidth', 1.4, 'Color', band_colors(i, :));
end

for i = 2:numel(tick_s) - 1
    xline(ax, tick_s(i), '-', 'Color', [0.70, 0.70, 0.70], 'LineWidth', 0.9);
end

xlim(ax, [s(1), s(end)]);
xticks(ax, tick_s.');
xticklabels(ax, labels);
xlabel(ax, 'Wave vector', 'FontName', 'Times New Roman', 'FontSize', 16);
ylabel(ax, 'Frequency (Hz)', 'FontName', 'Times New Roman', 'FontSize', 16);
title(ax, sprintf('%s band diagram', strrep(case_id, '_', '\_')), ...
    'FontName', 'Times New Roman', 'FontSize', 16, 'FontWeight', 'normal');
grid(ax, 'on');

try
    exportgraphics(fig, png_file, 'Resolution', 300, 'BackgroundColor', 'white');
catch
    saveas(fig, png_file);
end

try
    exportgraphics(fig, svg_file, 'ContentType', 'vector', 'BackgroundColor', 'white');
catch
end

meta = struct();
meta.case_id = case_id;
meta.symmetry_group = getOptionalField(bz, 'symmetry_group', '');
meta.path_name = bz.path_name;
meta.tick_coordinate = tick_s.';
meta.tick_labels = labels;
meta.num_kpoints = size(freqs, 1);
meta.num_bands = size(freqs, 2);
writeJson(meta_file, meta);

files = struct();
files.band_diagram_png = png_file;
if exist(svg_file, 'file')
    files.band_diagram_svg = svg_file;
end
files.band_diagram_meta_json = meta_file;
end

function labels = normalizeLabels(raw_labels)
labels = raw_labels;
for i = 1:numel(labels)
    label = string(labels{i});
    if strcmpi(label, "G") || strcmpi(label, "Gamma")
        labels{i} = '\Gamma';
    else
        labels{i} = char(label);
    end
end
end

function writeJson(filename, data)
fid = fopen(filename, 'w');
if fid < 0
    error('PlotAcousticBandDiagram:CannotOpenMeta', ...
        'Cannot open output file: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonencode(data));
end

function closeFigure(fig)
if ishghandle(fig)
    close(fig);
end
end

function value = getOptionalField(data, field_name, default_value)
if isfield(data, field_name)
    value = data.(field_name);
else
    value = default_value;
end
end
