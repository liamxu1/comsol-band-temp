function result = RunAcousticBandFromTensor(tensor_file, symmetry_group, unit_cell_length, varargin)
%RUNACOUSTICBANDFROMTENSOR Full acoustic band pipeline from a saved .mat case.

if nargin < 2 || isempty(symmetry_group)
    symmetry_group = '';
end
if nargin < 3 || isempty(unit_cell_length)
    unit_cell_length = 1.0;
end

sample = LoadBsplineTensorCase(tensor_file, symmetry_group);
if isempty(symmetry_group)
    symmetry_group = sample.symmetry_group;
end

[~, name] = fileparts(tensor_file);
cfg = AcousticBandConfig(varargin{:});
cfg.unit_cell_length = unit_cell_length;
if isempty(cfg.case_id)
    cfg.case_id = name;
end

result = RunAcousticBandFromCoefficients(sample.coefficients, symmetry_group, ...
    unit_cell_length, cfg);
result.input_sample = sample;
result.dataset_file = SaveAcousticBandDatasetFile(result, sample, cfg);

if isfield(sample, 'xPhys_HD_Final')
    result.geometry_validation = CompareReconstructionToTensor( ...
        result.geometry.xPhysCanonical, sample.xPhys_HD_Final, cfg);
end

if isstruct(result.output_files)
    result.output_files.dataset_mat = result.dataset_file;
else
    result.output_files = struct('dataset_mat', result.dataset_file);
end

end
