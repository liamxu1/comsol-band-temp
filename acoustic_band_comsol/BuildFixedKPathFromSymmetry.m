function bz = BuildFixedKPathFromSymmetry(symmetry_group, unit_cell_length, total_k_points, cfg)
%BUILDFIXEDKPATHFROMSYMMETRY Build a fixed-size BZ path chosen by symmetry.

if nargin < 4 || isempty(cfg)
    cfg = AcousticBandConfig('unit_cell_length', unit_cell_length);
end

base_bz = GetBrillouinZonePath(symmetry_group, unit_cell_length, cfg);
bz = InterpolateBrillouinZonePath(base_bz, total_k_points);
end
