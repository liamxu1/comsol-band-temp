function paths = portable_add_paths()
%PORTABLE_ADD_PATHS Add portable package paths.

runner_dir = fileparts(mfilename('fullpath'));
package_root = fileparts(runner_dir);

addpath(fullfile(package_root, 'portable_runner'));
addpath(fullfile(package_root, 'acoustic_band_comsol'));
addpath(fullfile(package_root, 'acoustic_band_comsol', 'validation'));
addpath(fullfile(package_root, 'FEA_Engine', 'Math_Utils'));
addpath(fullfile(package_root, 'FEA_Engine', 'Symmetry_Engine'));

paths = struct();
paths.package_root = package_root;
paths.runner_dir = runner_dir;
paths.acoustic_dir = fullfile(package_root, 'acoustic_band_comsol');
paths.output_dir_default = fullfile(package_root, 'output');
end
