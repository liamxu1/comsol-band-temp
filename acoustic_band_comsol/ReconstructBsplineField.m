function geom = ReconstructBsplineField(coefficients, symmetry_group, cfg)
%RECONSTRUCTBSPLINEFIELD Reconstruct the canonical and display-aligned fields.
%
% coefficients may be a 400x1 vector or a 20x20 coefficient matrix. The
% output xPhysCanonical follows the saved tensor convention: 1=solid,
% 0=void. solidMaskDisplay is flipud(xPhysCanonical>=threshold), matching
% the black material silhouette in *_structure_HD.png.

if nargin < 3 || isempty(cfg)
    cfg = AcousticBandConfig();
end
AddAcousticBandPaths();

[sg_name, phi_degrees, n_ops, orbit_func] = GetSpaceGroupConfig(symmetry_group);

coeff = normalizeCoefficients(coefficients, cfg.coeff_grid_size);
nx = cfg.grid_resolution;
ny = cfg.grid_resolution;
deg_u = cfg.bspline_degree(1);
deg_v = cfg.bspline_degree(2);
coff_nx = cfg.coeff_grid_size(1);
coff_ny = cfg.coeff_grid_size(2);

B = PrecomputeBasisMatrix_Unified(nx, ny, coff_nx, coff_ny, ...
    deg_u, deg_v, orbit_func, n_ops);
raw_vec = B * coeff;
raw = reshape(raw_vec, nx, ny);

den = tanh(cfg.beta * cfg.eta) + tanh(cfg.beta * (1 - cfg.eta));
projected = (tanh(cfg.beta * cfg.eta) + tanh(cfg.beta * (raw - cfg.eta))) ./ den;
projected = max(0, min(1, projected));

geom = struct();
geom.symmetry_group = sg_name;
geom.phi_degrees = phi_degrees;
geom.unit_cell_length = cfg.unit_cell_length;
geom.xPhysRaw = raw;
geom.xPhysCanonical = projected;
geom.solidMaskCanonical = interpretSolidMask(projected, cfg);
geom.solidMaskDisplay = flipud(geom.solidMaskCanonical);
geom.displayImage = flipud(1 - double(geom.solidMaskCanonical));
geom.voidMaskForComsol = ~geom.solidMaskDisplay;
geom.volume_fraction = mean(projected(:));
geom.solid_volume_fraction = mean(geom.solidMaskCanonical(:));
geom.coefficients = coeff;
geom.config = cfg;

end

function solid_mask = interpretSolidMask(projected, cfg)
base_mask = projected >= cfg.threshold;
if isfield(cfg, 'solid_phase_value') && isequal(cfg.solid_phase_value, 0)
    solid_mask = ~base_mask;
else
    solid_mask = base_mask;
end
end

function coeff = normalizeCoefficients(coefficients, coeff_grid_size)
if isvector(coefficients)
    coeff = coefficients(:);
elseif isequal(size(coefficients), coeff_grid_size)
    coeff = coefficients(:);
elseif isequal(size(coefficients), fliplr(coeff_grid_size))
    coeff = coefficients(:);
else
    error('ReconstructBsplineField:InvalidCoefficientSize', ...
        'Expected a 400x1 vector or a %dx%d matrix.', ...
        coeff_grid_size(1), coeff_grid_size(2));
end

expected = prod(coeff_grid_size);
if numel(coeff) ~= expected
    error('ReconstructBsplineField:InvalidCoefficientCount', ...
        'Expected %d coefficients, got %d.', expected, numel(coeff));
end
end
