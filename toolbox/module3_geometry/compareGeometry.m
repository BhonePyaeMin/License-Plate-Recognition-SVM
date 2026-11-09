function fig = compareGeometry(I)
%COMPAREGEOMETRY  Show Module 3 results: transforms, interpolation methods and distortion.
%   fig = COMPAREGEOMETRY(I)

I = toDouble(I);
[h, w, ~] = size(I);
fig = figure('Name', 'Module 3 - Geometric transformations', 'Color', 'w', 'Position', [60 60 1200 700]);
items = {
    'Original',                        I
    'Translate (+40, +25)',            geometricTransforms(I, 'translate', 40, 25)
    'Scale x1.4 about centre',         geometricTransforms(I, 'scale', 1.4)
    'Rotate 15 deg (same canvas)',     geometricTransforms(I, 'rotate', 15)
    'Rotate 15 deg (full canvas)',     geometricTransforms(I, 'rotate', 15, 'bilinear', 'full')
    'Shear x 0.25',                    geometricTransforms(I, 'shear', 0.25, 0)
    'Forward map (scale 1.6, holes)',  warpImage(I, [1.6 0 0; 0 1.6 0; 0 0 1], [h w], 'nearest', 'forward')
    'Reverse map (scale 1.6)',         warpImage(I, [1.6 0 0; 0 1.6 0; 0 0 1], [h w], 'bilinear', 'reverse')
    'Barrel distortion (k1 = -0.3)',   radialDistortion(I, -0.3, 0, 'apply')
    'Distortion corrected',            radialDistortion(radialDistortion(I, -0.3, 0, 'apply'), -0.3, 0, 'correct')
    'Nearest, 4x zoom crop',           zoomCrop(I, 'nearest')
    'Bicubic, 4x zoom crop',           zoomCrop(I, 'bicubic')
    };
for k = 1:size(items,1)
    showImage(subplot(3,4,k), items{k,2}, items{k,1});
end
end

function Z = zoomCrop(I, method)
% Crop a small centre patch and enlarge it 4x to expose interpolation artefacts.
[h, w, ~] = size(I);
r = round(h/2) + (-12:11);  c = round(w/2) + (-16:15);
Z = imResize(I(r, c, :), 4, method);
end
