function sample = LoadBsplineTensorCase(tensor_file, symmetry_group)
%LOADBSPLINETENSORCASE Load one bspline/tensors/*.mat sample.

if nargin < 2
    symmetry_group = '';
end

data = load(tensor_file);
if ~isfield(data, 'coffi_total')
    error('LoadBsplineTensorCase:MissingCoefficients', ...
        'The tensor file does not contain coffi_total: %s', tensor_file);
end

if isempty(symmetry_group)
    symmetry_group = InferBsplineSymmetryGroup(tensor_file);
end

sample = struct();
sample.tensor_file = tensor_file;
sample.symmetry_group = symmetry_group;
sample.coefficients = data.coffi_total;
sample.data = data;

if isfield(data, 'xPhys_HD_Final')
    sample.xPhys_HD_Final = data.xPhys_HD_Final;
end
if isfield(data, 'Q')
    sample.Q = data.Q;
end
if isfield(data, 'real_volfrac')
    sample.real_volfrac = data.real_volfrac;
end

end
