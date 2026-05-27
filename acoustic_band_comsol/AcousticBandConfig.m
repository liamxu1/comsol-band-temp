function cfg = AcousticBandConfig(varargin)
%ACOUSTICBANDCONFIG Defaults for B-spline acoustic band simulations.
%
% The geometry convention follows bspline/AGENTS.md:
%   xPhysCanonical: saved .mat field, 1 = solid, 0 = void
%   display image:  flipud(1 - xPhysCanonical)
%   COMSOL image:   flipud(xPhysCanonical) for solid reference; the acoustic
%                   geometry itself is built from the void/fluid mask.

cfg = struct();

% Geometry reconstruction.
cfg.unit_cell_length = 1.0;
cfg.grid_resolution = 480;
cfg.coeff_grid_size = [20, 20];
cfg.bspline_degree = [3, 3];
cfg.beta = 200;
cfg.eta = 0.5;
cfg.threshold = 0.5;
cfg.solid_phase_value = 1;            % 1: projected>=threshold is solid; 0: inverse

% Geometry cleanup and COMSOL image-to-geometry conversion.
cfg.geometry_method = 'mphimage2geom';
cfg.solve_phase = 'void';              % Pressure acoustics is solved in void/fluid.
cfg.geometry_mindist_pixels = 2.0;
cfg.geometry_minarea_fraction = 1e-5;
cfg.geometry_curve_type = 'polygon';

% Acoustic medium. These are fluid properties for the void domain.
cfg.sound_speed = 343;                 % m/s
cfg.density = 1.21;                    % kg/m^3

% Bloch/eigenfrequency sweep.
cfg.path_points_per_segment = 12;
cfg.total_k_points = [];
cfg.num_eigenfrequencies = 8;
cfg.search_frequency = 0;              % Hz, eigenfrequency shift.
cfg.mesh_max_size_fraction = 1 / 35;
cfg.mesh_min_size_fraction = 1 / 300;

% Runtime and outputs.
cfg.run_comsol = true;
cfg.save_model = true;
cfg.write_standard_outputs = true;
cfg.output_dir = fullfile(pwd, 'acoustic_band_output');
cfg.case_id = '';
cfg.verbose = true;

% Field sampling defaults for dataset generation.
cfg.field_grid_resolution = 256;
cfg.field_expression_candidates = {'acpr.p_t', 'p', 'acpr.p', 'abs(acpr.p_t)', 'abs(p)'};

if nargin == 1 && isstruct(varargin{1})
    cfg = mergeStruct(cfg, varargin{1});
elseif mod(nargin, 2) == 0
    for i = 1:2:nargin
        key = char(varargin{i});
        cfg.(key) = varargin{i + 1};
    end
else
    error('AcousticBandConfig:InvalidInput', ...
        'Use a struct or name-value pairs.');
end

end

function out = mergeStruct(out, in)
names = fieldnames(in);
for i = 1:numel(names)
    out.(names{i}) = in.(names{i});
end
end
