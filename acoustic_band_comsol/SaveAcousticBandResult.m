function files = SaveAcousticBandResult(result, cfg)
%SAVEACOUSTICBANDRESULT Save reusable MAT/CSV/PNG-style validation outputs.

if nargin < 2 || isempty(cfg)
    cfg = result.config;
end
if ~exist(cfg.output_dir, 'dir')
    mkdir(cfg.output_dir);
end

case_id = cfg.case_id;
files = struct();

mat_file = fullfile(cfg.output_dir, [case_id, '_result.mat']);
result_to_save = result; %#ok<NASGU>
if isfield(result_to_save, 'comsol') && isstruct(result_to_save.comsol) && isfield(result_to_save.comsol, 'model')
    result_to_save.comsol = rmfield(result_to_save.comsol, 'model');
end
if exist(mat_file, 'file')
    delete(mat_file);
end
try
    save(mat_file, 'result_to_save', '-v7.3');
catch
    if exist(mat_file, 'file')
        delete(mat_file);
    end
    save(mat_file, 'result_to_save', '-v7');
end
files.result_mat = mat_file;

display_png = fullfile(cfg.output_dir, [case_id, '_display_reference.png']);
imwrite(result.geometry.displayImage, display_png);
files.display_reference_png = display_png;

solid_png = fullfile(cfg.output_dir, [case_id, '_solid_mask_for_comsol.png']);
imwrite(uint8(result.geometry.solidMaskDisplay) * 255, solid_png);
files.solid_mask_for_comsol_png = solid_png;

void_png = fullfile(cfg.output_dir, [case_id, '_void_mask_for_comsol.png']);
imwrite(uint8(result.geometry.voidMaskForComsol) * 255, void_png);
files.void_mask_for_comsol_png = void_png;

bz_csv = fullfile(cfg.output_dir, [case_id, '_bz_path.csv']);
writeMatrixWithHeader(bz_csv, ...
    [result.brillouin_zone.path_coordinate(:), result.brillouin_zone.k_points], ...
    {'s', 'kx_1_per_m', 'ky_1_per_m'});
files.bz_path_csv = bz_csv;

if isfield(result, 'band_frequencies_hz') && ~isempty(result.band_frequencies_hz)
    band_csv = fullfile(cfg.output_dir, [case_id, '_bands_hz.csv']);
    data = [result.brillouin_zone.path_coordinate(:), ...
        result.brillouin_zone.k_points, result.band_frequencies_hz];
    headers = [{'s', 'kx_1_per_m', 'ky_1_per_m'}, ...
        arrayfun(@(i) sprintf('band_%02d_hz', i), ...
        1:size(result.band_frequencies_hz, 2), 'UniformOutput', false)];
    writeMatrixWithHeader(band_csv, data, headers);
    files.band_csv = band_csv;

    plot_files = PlotAcousticBandDiagram(result, cfg);
    plot_names = fieldnames(plot_files);
    for i = 1:numel(plot_names)
        files.(plot_names{i}) = plot_files.(plot_names{i});
    end
end

end

function writeMatrixWithHeader(filename, data, headers)
fid = fopen(filename, 'w');
if fid < 0
    error('SaveAcousticBandResult:CannotOpenFile', ...
        'Cannot open output file: %s', filename);
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', strjoin(headers, ','));
fmt = [repmat('%.16g,', 1, size(data, 2) - 1), '%.16g\n'];
for i = 1:size(data, 1)
    fprintf(fid, fmt, data(i, :));
end
end
