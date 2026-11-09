function ops = toolboxOperations()
%TOOLBOXOPERATIONS  Table of every operation offered by the GUI (and used by the tests).
%   ops = TOOLBOXOPERATIONS() returns a struct array with the fields
%     module  1 (enhancement) | 2 (segmentation & edges) | 3 (geometry)
%     name    text shown in the drop-down list
%     params  struct array (label, min, max, default) describing up to 3 sliders
%     run     function handle  [J, info] = run(I, p, ref)
%             I = input image (double RGB or gray), p = vector of slider values,
%             ref = reference image (used by histogram matching / registration)
%             J = result image, info = one-line text describing the result
%
%   Adding a new operation only needs one more entry here - the GUI builds its
%   controls from this table.

L = {};
par = @(label, lo, hi, def) struct('label', label, 'min', lo, 'max', hi, 'default', def);
none = struct('label', {}, 'min', {}, 'max', {}, 'default', {});
bin = @(B) repmat(double(B), [1 1 3]);

% =============================== Module 1 =====================================
L{end+1} = makeOp(1, 'Histogram equalisation', none, @(I,p,r) deal(histEqualize(I), 'Histogram flattened (V channel for colour)'));
L{end+1} = makeOp(1, 'Histogram matching (to reference)', none, @(I,p,r) deal(histMatch(I, refOrDefault(I, r)), 'Histogram matched to the reference image'));
L{end+1} = makeOp(1, 'Brightness / contrast', [par('Contrast gain', 0.2, 3, 1.3), par('Brightness', -0.5, 0.5, 0.05)], ...
    @(I,p,r) deal(grayTransform(I, 'linear', p(1), p(2)), sprintf('J = %.2f*(I-0.5)+0.5%+.2f', p(1), p(2))));
L{end+1} = makeOp(1, 'Gamma correction', par('Gamma', 0.2, 3, 0.6), @(I,p,r) deal(grayTransform(I, 'gamma', p(1)), sprintf('J = I^%.2f', p(1))));
L{end+1} = makeOp(1, 'Log transform', par('a', 1, 200, 50), @(I,p,r) deal(grayTransform(I, 'log', p(1)), 'Expands dark levels'));
L{end+1} = makeOp(1, 'Contrast stretching', [par('Low percentile', 0, 20, 1), par('High percentile', 80, 100, 99)], ...
    @(I,p,r) deal(grayTransform(I, 'stretch', p(1), p(2)), 'Percentile contrast stretch'));
L{end+1} = makeOp(1, 'Mean filter', par('Window size', 3, 15, 5), @(I,p,r) deal(smoothFilter(I, 'mean', round(p(1))), 'Box average'));
L{end+1} = makeOp(1, 'Gaussian filter', [par('Window size', 3, 21, 7), par('Sigma', 0.5, 6, 1.5)], ...
    @(I,p,r) deal(smoothFilter(I, 'gaussian', round(p(1)), p(2)), 'Gaussian smoothing'));
L{end+1} = makeOp(1, 'Median filter', par('Window size', 3, 9, 3), @(I,p,r) deal(smoothFilter(I, 'median', round(p(1))), 'Non-linear median'));
L{end+1} = makeOp(1, 'Laplacian sharpening', par('Amount', 0, 3, 1), @(I,p,r) deal(sharpenFilter(I, 'laplacian', p(1)), 'J = I - amount*Laplacian(I)'));
L{end+1} = makeOp(1, 'High-pass sharpening', par('Amount', 0, 3, 1), @(I,p,r) deal(sharpenFilter(I, 'highpass', p(1)), '3x3 high-pass kernel added back'));
L{end+1} = makeOp(1, 'Unsharp masking', par('Amount', 0, 4, 1.5), @(I,p,r) deal(sharpenFilter(I, 'unsharp', p(1)), 'High-boost filtering'));
L{end+1} = makeOp(1, 'Frequency low-pass (Butterworth)', par('Cut-off', 0.02, 0.8, 0.15), ...
    @(I,p,r) deal(freqFilter(I, 'lowpass', p(1), 'butterworth'), sprintf('FFT low-pass, cut-off %.2f', p(1))));
L{end+1} = makeOp(1, 'Frequency high-pass (Butterworth)', par('Cut-off', 0.02, 0.8, 0.10), ...
    @(I,p,r) deal(freqFilter(I, 'highpass', p(1), 'butterworth'), sprintf('FFT high-pass, cut-off %.2f', p(1))));
L{end+1} = makeOp(1, 'Frequency band-pass (Gaussian)', [par('Low cut-off', 0.01, 0.5, 0.05), par('High cut-off', 0.05, 0.9, 0.30)], ...
    @(I,p,r) deal(freqFilter(I, 'bandpass', [p(1) p(2)], 'gaussian'), 'FFT band-pass'));
L{end+1} = makeOp(1, 'Add Gaussian noise', par('Sigma', 0, 0.3, 0.05), @(I,p,r) deal(addNoise(I, 'gaussian', p(1)), 'Test input for the denoising filters'));
L{end+1} = makeOp(1, 'Add salt-and-pepper noise', par('Density', 0, 0.4, 0.05), @(I,p,r) deal(addNoise(I, 'saltpepper', p(1)), 'Test input for the median filter'));

% =============================== Module 2 =====================================
L{end+1} = makeOp(2, 'Sobel edges', par('Threshold (0 = Otsu)', 0, 1, 0), @(I,p,r) edgeOp(I, 'sobel', p(1)));
L{end+1} = makeOp(2, 'Prewitt edges', par('Threshold (0 = Otsu)', 0, 1, 0), @(I,p,r) edgeOp(I, 'prewitt', p(1)));
L{end+1} = makeOp(2, 'Canny edges', [par('High threshold (0 = auto)', 0, 1, 0), par('Sigma', 0.5, 4, 1.4)], @(I,p,r) cannyOp(I, p));
L{end+1} = makeOp(2, 'Otsu threshold', none, @(I,p,r) otsuOp(I));
L{end+1} = makeOp(2, 'Adaptive threshold', [par('Window', 5, 101, 31), par('Offset', 0, 0.3, 0.05)], ...
    @(I,p,r) deal(bin(adaptiveThreshold(I, round(p(1)), p(2), 'dark')), 'Dark foreground vs local mean'));
L{end+1} = makeOp(2, 'Region growing (from centre)', par('Tolerance', 0.01, 0.5, 0.12), ...
    @(I,p,r) regionOp(I, p(1)));
L{end+1} = makeOp(2, 'Colour segmentation: white (HSV)', none, @(I,p,r) deal(bin(colorSegment(I, 'HSV', 'white')), 'Low saturation, high value'));
L{end+1} = makeOp(2, 'Colour segmentation: yellow (HSV)', none, @(I,p,r) deal(bin(colorSegment(I, 'HSV', 'yellow')), 'Hue 0.09-0.20'));
L{end+1} = makeOp(2, 'Colour segmentation: blue (HSV)', none, @(I,p,r) deal(bin(colorSegment(I, 'HSV', 'blue')), 'Hue 0.52-0.72'));
L{end+1} = makeOp(2, 'Colour segmentation: red (RGB range)', none, @(I,p,r) deal(bin(colorSegment(I, 'RGB', [0.55 1 0 0.35 0 0.35])), 'R high, G and B low'));
L{end+1} = makeOp(2, 'Morphology: dilation', par('Disk radius', 1, 10, 2), @(I,p,r) morphGui(I, 'dilate', p(1)));
L{end+1} = makeOp(2, 'Morphology: erosion', par('Disk radius', 1, 10, 2), @(I,p,r) morphGui(I, 'erode', p(1)));
L{end+1} = makeOp(2, 'Morphology: opening', par('Disk radius', 1, 10, 2), @(I,p,r) morphGui(I, 'open', p(1)));
L{end+1} = makeOp(2, 'Morphology: closing', par('Disk radius', 1, 10, 3), @(I,p,r) morphGui(I, 'close', p(1)));
L{end+1} = makeOp(2, 'Morphology: gradient (outline)', par('Disk radius', 1, 6, 1), @(I,p,r) morphGui(I, 'gradient', p(1)));
L{end+1} = makeOp(2, 'Shape segmentation (plate-like blobs)', [], @(I,p,r) shapeOp(I));

% =============================== Module 3 =====================================
L{end+1} = makeOp(3, 'Translation', [par('dx (px)', -200, 200, 40), par('dy (px)', -200, 200, 25)], ...
    @(I,p,r) deal(geometricTransforms(I, 'translate', p(1), p(2)), sprintf('Shift by (%.0f, %.0f)', p(1), p(2))));
L{end+1} = makeOp(3, 'Scaling / zoom', par('Scale', 0.2, 3, 1.5), @(I,p,r) deal(geometricTransforms(I, 'scale', p(1)), sprintf('Zoom x%.2f about the centre', p(1))));
L{end+1} = makeOp(3, 'Rotation', par('Angle (deg)', -90, 90, 15), @(I,p,r) deal(geometricTransforms(I, 'rotate', p(1)), sprintf('Rotate %.0f deg', p(1))));
L{end+1} = makeOp(3, 'Rotation (full canvas)', par('Angle (deg)', -90, 90, 15), @(I,p,r) deal(geometricTransforms(I, 'rotate', p(1), 'bilinear', 'full'), 'Canvas enlarged'));
L{end+1} = makeOp(3, 'Shear', [par('Shear x', -0.6, 0.6, 0.25), par('Shear y', -0.6, 0.6, 0)], ...
    @(I,p,r) deal(geometricTransforms(I, 'shear', p(1), p(2)), 'Affine shear'));
L{end+1} = makeOp(3, 'Affine (rotate + scale + shear)', [par('Angle (deg)', -45, 45, 10), par('Scale', 0.5, 1.5, 0.9), par('Shear', -0.4, 0.4, 0.15)], ...
    @(I,p,r) affineOp(I, p));
L{end+1} = makeOp(3, 'Forward mapping (scale, shows holes)', par('Scale', 0.5, 3, 1.6), ...
    @(I,p,r) deal(warpImage(I, diag([p(1) p(1) 1]), [size(I,1) size(I,2)], 'nearest', 'forward'), 'Forward mapping leaves holes'));
L{end+1} = makeOp(3, 'Reverse mapping (scale)', par('Scale', 0.5, 3, 1.6), ...
    @(I,p,r) deal(warpImage(I, diag([p(1) p(1) 1]), [size(I,1) size(I,2)], 'bilinear', 'reverse'), 'Reverse mapping: no holes'));
L{end+1} = makeOp(3, 'Resize: nearest neighbour', par('Scale', 0.1, 4, 2), @(I,p,r) deal(imResize(I, p(1), 'nearest'), 'Blocky when enlarging'));
L{end+1} = makeOp(3, 'Resize: bilinear', par('Scale', 0.1, 4, 2), @(I,p,r) deal(imResize(I, p(1), 'bilinear'), 'Smooth, slightly soft'));
L{end+1} = makeOp(3, 'Resize: bicubic', par('Scale', 0.1, 4, 2), @(I,p,r) deal(imResize(I, p(1), 'bicubic'), 'Sharpest of the three'));
L{end+1} = makeOp(3, 'Radial distortion: simulate', [par('k1', -0.6, 0.6, -0.25), par('k2', -0.3, 0.3, 0)], ...
    @(I,p,r) deal(radialDistortion(I, p(1), p(2), 'apply'), 'Barrel (k1<0) / pincushion (k1>0)'));
L{end+1} = makeOp(3, 'Radial distortion: correct', [par('k1', -0.6, 0.6, -0.25), par('k2', -0.3, 0.3, 0)], ...
    @(I,p,r) deal(radialDistortion(I, p(1), p(2), 'correct'), 'Reverse-map undistortion'));
L{end+1} = makeOp(3, 'Image registration (features)', none, @(I,p,r) registerOp(I, r, 'features'));
L{end+1} = makeOp(3, 'Image registration (phase corr.)', none, @(I,p,r) registerOp(I, r, 'phase'));
ops = [L{:}];
end

function op = makeOp(module, name, params, fn)
% One entry of the operation table.
op = struct('module', module, 'name', name, 'params', {params}, 'run', fn);
end

% ---------------------------------------------------------------------------
function r = refOrDefault(I, r)
% Histogram-matching reference: the loaded reference image, else a brightened copy.
if isempty(r), r = grayTransform(I, 'gamma', 0.5); end
end

function [J, info] = edgeOp(I, method, thr)
if thr <= 0, thr = []; end
E = edgeDetect(I, method, thr);
J = repmat(double(E), [1 1 3]);
info = sprintf('%s: %d edge pixels', method, nnz(E));
end

function [J, info] = cannyOp(I, p)
thr = p(1); if thr <= 0, thr = []; end
E = edgeDetect(I, 'canny', thr, p(2));
J = repmat(double(E), [1 1 3]);
info = sprintf('Canny: %d edge pixels', nnz(E));
end

function [J, info] = otsuOp(I)
[t, B, eta] = otsuThreshold(I);
J = repmat(double(B), [1 1 3]);
info = sprintf('Otsu level %.3f (separability %.2f)', t, eta);
end

function [J, info] = regionOp(I, tol)
G = toGray(I);
[B, n] = regionGrow(G, round(size(G)/2), tol);
J = toDouble(I);
if size(J,3) == 1, J = repmat(J, [1 1 3]); end
J(:,:,1) = max(J(:,:,1), 0.9*double(B));                   % tint the region red
J(:,:,2) = J(:,:,2) .* (1 - 0.6*double(B));
J(:,:,3) = J(:,:,3) .* (1 - 0.6*double(B));
info = sprintf('Region covers %.1f %% of the image (%d iterations)', 100*mean(B(:)), n);
end

function [J, info] = morphGui(I, op, r)
B = otsuBinary(I);
J = repmat(double(morphOp(B, op, makeSE('disk', round(r)))), [1 1 3]);
info = sprintf('%s of the Otsu-binarised image, disk radius %d', op, round(r));
end

function [J, info] = shapeOp(I)
E = edgeDetect(I, 'canny');
M = fillHoles(morphOp(morphOp(E, 'close', makeSE('rect', [3 25])), 'close', makeSE('disk', 2)));
[B, keep] = filterComponents(M, 'MinAspect', 2, 'MaxAspect', 8, 'MinExtent', 0.5, 'MinArea', 150);
J = repmat(double(B), [1 1 3]);
info = sprintf('%d plate-shaped component(s) kept', nnz(keep));
end

function B = otsuBinary(I)
G = toGray(I);
[~, B] = otsuThreshold(G);
end

function [J, info] = affineOp(I, p)
a = p(1)*pi/180;
A = p(2) * [cos(a) sin(a); -sin(a) cos(a)] * [1 p(3); 0 1];
[h, w, ~] = size(I);
c = [(w+1)/2; (h+1)/2];
t = c - A * c;                                              % keep the image centre fixed
J = geometricTransforms(I, 'affine', [A t]);
info = sprintf('Affine: rotate %.0f deg, scale %.2f, shear %.2f', p(1), p(2), p(3));
end

function [J, info] = registerOp(I, ref, method)
if isempty(ref)                                             % no reference loaded: make one by moving I
    ref = geometricTransforms(I, 'rotate', 6);
    ref = geometricTransforms(ref, 'translate', 14, -9);
    note = '(reference = rotated+shifted copy of the image) ';
else
    note = '';
end
[~, J, inf0] = registerImages(I, ref, method);
if isfield(inf0, 'inliers')
    info = sprintf('%sfeature matches: %d, inliers: %d', note, inf0.matches, inf0.inliers);
else
    info = sprintf('%sshift found: dx=%d, dy=%d', note, inf0.shift(1), inf0.shift(2));
end
end
