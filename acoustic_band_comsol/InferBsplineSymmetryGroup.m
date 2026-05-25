function symmetry_group = InferBsplineSymmetryGroup(input_name)
%INFERBSPLINESYMMETRYGROUP Infer wallpaper group from a tensor file name.
%
% Supported examples:
%   01_p4_100139_tensor.mat
%   p4_Vol0.53_K0.0000_Sample_103461_tensor.mat

if isstring(input_name)
    input_name = char(input_name);
end

[~, name, ~] = fileparts(input_name);
name = regexprep(name, '_tensor$', '');

candidates = { ...
    'p6mm', 'p31m', 'p3m1', ...
    'p4mm', 'p4gm', ...
    'c2mm', 'p2mm', 'p2mg', 'p2gg', ...
    'p1', 'p2', 'pm', 'pg', 'cm', 'p4', 'p3', 'p6'};

symmetry_group = '';
for i = 1:numel(candidates)
    token = candidates{i};
    pattern = ['(^|_)', regexptranslate('escape', token), '(_|$)'];
    if ~isempty(regexp(lower(name), pattern, 'once'))
        symmetry_group = token;
        return;
    end
end

error('InferBsplineSymmetryGroup:CannotInfer', ...
    'Cannot infer symmetry group from file name: %s', input_name);
end
