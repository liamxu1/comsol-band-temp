function root_dir = AddAcousticBandPaths()
%ADDACOUSTICBANDPATHS Add this module and the existing B-spline FEA helpers.

root_dir = fileparts(fileparts(mfilename('fullpath')));
module_dir = fullfile(root_dir, 'acoustic_band_comsol');

addIfExists(module_dir);
addIfExists(fullfile(module_dir, 'validation'));
addIfExists(fullfile(module_dir, 'tests'));
addIfExists(fullfile(root_dir, 'FEA_Engine', 'Math_Utils'));
addIfExists(fullfile(root_dir, 'FEA_Engine', 'Symmetry_Engine'));

end

function addIfExists(path_str)
if exist(path_str, 'dir')
    addpath(path_str);
end
end
