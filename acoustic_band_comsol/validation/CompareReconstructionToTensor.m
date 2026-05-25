function metrics = CompareReconstructionToTensor(reconstructed_xPhys, reference_xPhys, cfg)
%COMPARERECONSTRUCTIONTOTENSOR Compare reconstructed field to saved tensor field.

if nargin < 3 || isempty(cfg)
    cfg = AcousticBandConfig();
end

ref = double(reference_xPhys);
rec = double(reconstructed_xPhys);
metrics = struct();
if ~isequal(size(ref), size(rec))
    [xq, yq] = meshgrid(linspace(1, size(ref, 2), size(rec, 2)), ...
        linspace(1, size(ref, 1), size(rec, 1)));
    ref = interp2(ref, xq, yq, 'linear');
    metrics.reference_resampled = true;
    metrics.reference_original_size = size(reference_xPhys);
else
    metrics.reference_resampled = false;
end

ref_bin = ref >= cfg.threshold;
rec_bin = rec >= cfg.threshold;

inter = nnz(ref_bin & rec_bin);
unionv = nnz(ref_bin | rec_bin);
if unionv == 0
    iou = 1;
else
    iou = inter / unionv;
end

metrics.mean_absolute_error = mean(abs(rec(:) - ref(:)));
metrics.max_absolute_error = max(abs(rec(:) - ref(:)));
metrics.binary_iou = iou;
metrics.binary_mismatch_fraction = nnz(ref_bin ~= rec_bin) / numel(ref_bin);
metrics.reference_volume_fraction = mean(ref(:));
metrics.reconstructed_volume_fraction = mean(rec(:));
metrics.flipud_display_relation = 'display material mask = flipud(xPhysCanonical >= threshold)';

end
