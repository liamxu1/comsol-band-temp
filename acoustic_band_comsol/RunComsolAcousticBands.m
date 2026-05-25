function sim = RunComsolAcousticBands(geom, bz, cfg)
%RUNCOMSOLACOUSTICBANDS Build a COMSOL model and sweep Bloch wave vectors.

if nargin < 3 || isempty(cfg)
    cfg = geom.config;
end

[model, periodic_pairs] = BuildComsolAcousticBandModel(geom, cfg);
k_points = bz.k_points;

ConfigureComsolKPathSweep(model, bz, cfg);

if cfg.verbose
    fprintf('COMSOL internal Bloch sweep: %d k-points, %d bands, path %s\n', ...
        size(k_points, 1), cfg.num_eigenfrequencies, bz.path_name);
end

try
    model.study('std1').run;
catch ME
    error('RunComsolAcousticBands:SweepFailed', ...
        'COMSOL internal k-path parametric sweep failed: %s', ME.message);
end

[freqs, status, extraction] = ExtractComsolEigenfrequencySweep(model, ...
    cfg.num_eigenfrequencies, size(k_points, 1));

AddComsolBandResults(model, bz, freqs, cfg);

sim = struct();
sim.model = model;
sim.k_points = k_points;
sim.path_coordinate = bz.path_coordinate;
sim.band_frequencies_hz = freqs;
sim.status = status;
sim.extraction = extraction;
sim.mode_fields = [];
sim.periodic_pairs = periodic_pairs;
sim.periodic_x = periodic_pairs.periodic_x;
sim.periodic_y = periodic_pairs.periodic_y;

try
    sim.mode_fields = ExtractComsolModeFieldStack(model, cfg, freqs, bz);
catch ME
    sim.mode_fields = struct( ...
        'data', [], ...
        'status', "failed: " + string(ME.message), ...
        'expression', '', ...
        'grid_resolution', [cfg.field_grid_resolution, cfg.field_grid_resolution]);
    warning('RunComsolAcousticBands:ModeFieldExtractionFailed', ...
        'Could not extract sampled mode fields: %s', ME.message);
end

if cfg.save_model
    if ~exist(cfg.output_dir, 'dir')
        mkdir(cfg.output_dir);
    end
    mphsave(model, fullfile(cfg.output_dir, [cfg.case_id, '_acoustic_band.mph']));
end

end
