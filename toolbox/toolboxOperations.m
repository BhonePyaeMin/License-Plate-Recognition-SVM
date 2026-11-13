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

% ====================== comparison views (one picture, several tiles) ====================
% The Result shows the methods side by side; the GUI writes the name of every tile into the tile.
L{end+1} = makeCmp(1, 'Compare: enhancement methods', @cmpEnhance, [3 3], ...
    {'Original', 'Hist. equalised', 'Hist. matched', 'Gamma 0.5', 'Median 3x3', 'Gaussian 5x5', 'Laplacian sharpen', 'Low-pass', 'High-pass'});
L{end+1} = makeCmp(2, 'Compare: edge detectors', @cmpEdges, [2 2], ...
    {'Original (gray)', 'Sobel', 'Prewitt', 'Canny'});
L{end+1} = makeCmp(2, 'Compare: segmentation methods', @cmpSegment, [2 3], ...
    {'Original', 'Otsu', 'Adaptive', 'Region growing', 'White (HSV)', 'Edges + closing'});
L{end+1} = makeCmp(3, 'Compare: geometric transforms', @cmpGeom, [3 3], ...
    {'Original', 'Translation', 'Scaling x1.4', 'Rotation 15 deg', 'Shear 0.25', 'Affine', 'Forward (holes)', 'Reverse mapping', 'Distortion fixed'});
L{end+1} = makeCmp(3, 'Compare: interpolation (zoom)', @cmpInterp, [2 2], ...
    {'Original (framed)', 'Nearest', 'Bilinear', 'Bicubic'});

ops = [L{:}];
H = opHelp();
for k = 1:numel(ops)
    if isKey(H, ops(k).name), ops(k).help = H(ops(k).name); end
end
end

function op = makeOp(module, name, params, fn)
% One entry of the operation table (help = what it does and when to use it; tiles/grid only for the comparison views).
op = struct('module', module, 'name', name, 'params', {params}, 'run', fn, 'help', '', 'tiles', {{}}, 'grid', []);
end

function op = makeCmp(module, name, fn, grid, tiles)
% A comparison view: the function returns one picture made of grid(1) x grid(2) tiles.
op = makeOp(module, name, struct('label', {}, 'min', {}, 'max', {}, 'default', {}), @(I,p,r) fn(I, r));
op.tiles = tiles;  op.grid = grid;
end

function H = opHelp()
% what every operation does and when to use it (shown in the GUI under the Apply button, and in the guideline PDF)
c = {
 'Histogram equalisation',            'Spreads the grey levels over the whole range, so a flat, hazy or dark photo gets more contrast. Use it for low-contrast photos; it also lifts noise.'
 'Histogram matching (to reference)', 'Reshapes the grey-level histogram to look like a reference photo (Open reference...). Without a reference a brightened copy is used. Use it to give two photos the same exposure.'
 'Brightness / contrast',             'Linear grey-level change J = gain*(I-0.5)+0.5+offset. Raise the gain for flat photos and the offset for dark ones. Values pushed beyond black or white are lost.'
 'Gamma correction',                  'Power law J = I^gamma. Gamma below 1 brightens the dark areas, above 1 darkens washed-out areas. Use it for under- or over-exposed photos.'
 'Log transform',                     'J = log(1+a*I) expands the dark grey levels and compresses the bright ones. Use it when dark detail matters (night photos).'
 'Contrast stretching',               'Maps the chosen low and high percentiles to black and white and ignores a few extreme pixels. Use it for hazy or foggy photos.'
 'Mean filter',                       'Replaces every pixel by the average of its window. Reduces noise but blurs edges. Keep the window small (3 or 5) for grainy photos.'
 'Gaussian filter',                   'Weighted average with a bell-shaped window: a smoother blur than the mean filter. Use it for fine noise; sigma sets the amount of blur.'
 'Median filter',                     'Replaces every pixel by the median of its window. Best against salt-and-pepper dots and it keeps edges. Window 3 for few dots, 5 for many.'
 'Laplacian sharpening',              'Subtracts the Laplacian (second derivative) from the image, which makes edges steeper. Use it for soft photos; large amounts boost noise.'
 'High-pass sharpening',              'Adds a 3x3 high-pass (edge) kernel back to the image. Mild edge enhancement, similar to Laplacian sharpening.'
 'Unsharp masking',                   'Adds the difference between the photo and a blurred copy (high-boost filtering). The usual sharpening; an amount of 1 to 1.5 is safe.'
 'Frequency low-pass (Butterworth)',  'Keeps only the slow changes in the Fourier domain. Removes fine noise and screen pixel patterns; a low cut-off blurs strongly.'
 'Frequency high-pass (Butterworth)', 'Removes the slow changes and keeps fine detail and edges. Use it to see outlines or to flatten uneven light.'
 'Frequency band-pass (Gaussian)',    'Keeps the frequencies between the two cut-offs: removes slow shading and very fine noise at the same time.'
 'Add Gaussian noise',                'Test input: adds random grain. Apply it, press "Use result as input", then try the smoothing filters on it.'
 'Add salt-and-pepper noise',         'Test input: adds white and black dots. Then try the median filter, which removes them best.'
 'Sobel edges',                       'Edge strength from two 3x3 gradient kernels; the threshold (0 = Otsu) decides which edges are shown. Fast and simple, edges are thick.'
 'Prewitt edges',                     'Like Sobel but with equal weights in the kernel, so it is a little more sensitive to noise. Compare both on the same photo.'
 'Canny edges',                       'Smooths, finds the gradient, thins the edges and links them with two thresholds. The cleanest outline; sigma sets how much detail is kept.'
 'Otsu threshold',                    'Finds the grey level that best separates dark from bright pixels and makes a black-and-white picture. Use it when the light is even.'
 'Adaptive threshold',                'Compares every pixel with the mean of its neighbourhood, so shadows do not matter. A window of about 31 suits plates and text.'
 'Region growing (from centre)',      'Starts at the image centre and adds neighbours whose grey level is within the tolerance; the region is tinted red. Use it to cut out one object.'
 'Colour segmentation: white (HSV)',  'Keeps pixels with low saturation and high value: white plates and white bodywork.'
 'Colour segmentation: yellow (HSV)', 'Keeps pixels with hue 0.09 to 0.20: yellow plates.'
 'Colour segmentation: blue (HSV)',   'Keeps pixels with hue 0.52 to 0.72: blue plates and signs.'
 'Colour segmentation: red (RGB range)', 'Keeps pixels with high red and low green and blue (an RGB range): tail lights and red signs.'
 'Morphology: dilation',              'Grows the white regions with a disk. Joins broken characters; the radius sets the amount. Works on the Otsu-binarised image.'
 'Morphology: erosion',               'Shrinks the white regions and removes thin lines and small dots. Separates characters that touch.'
 'Morphology: opening',               'Erosion followed by dilation: removes small bright specks and keeps the size of the big shapes.'
 'Morphology: closing',               'Dilation followed by erosion: fills small holes and gaps inside the shapes.'
 'Morphology: gradient (outline)',    'Dilation minus erosion: draws the outline of the shapes.'
 'Shape segmentation (plate-like blobs)', 'Canny edges, closing, then a filter on aspect ratio, extent and area. Keeps the blobs that look like a licence plate.'
 'Translation',                       'Moves the image by dx and dy pixels (positive = right and down). The empty area is black.'
 'Scaling / zoom',                    'Enlarges or shrinks about the image centre by reverse mapping with bilinear interpolation.'
 'Rotation',                          'Turns the image about its centre; the corners are cut off. Use it to level a tilted plate.'
 'Rotation (full canvas)',            'The same rotation, but the canvas grows so no corner is lost.'
 'Shear',                             'Slants the image horizontally or vertically (an affine transform). Mimics a plate seen from the side.'
 'Affine (rotate + scale + shear)',   'Rotation, scaling and shear in one matrix. Straight lines stay straight and parallel lines stay parallel.'
 'Forward mapping (scale, shows holes)', 'Pushes every input pixel to its new place. Enlarging leaves holes: this is why reverse mapping is used.'
 'Reverse mapping (scale)',           'For every output pixel looks up the source position and interpolates. No holes appear.'
 'Resize: nearest neighbour',         'Copies the nearest pixel: fastest, blocky when enlarging.'
 'Resize: bilinear',                  'Averages the 4 nearest pixels: smooth, a little soft.'
 'Resize: bicubic',                   'Uses 16 neighbours with a cubic kernel: the sharpest of the three. Use it to enlarge a small plate.'
 'Radial distortion: simulate',       'Applies barrel (k1 < 0) or pincushion (k1 > 0) lens distortion, to test the correction.'
 'Radial distortion: correct',        'Undoes lens distortion for the given k1 and k2 by reverse mapping. Use it when straight lines look curved (wide-angle photos).'
 'Image registration (features)',     'Finds Harris corners in both images, matches them and fits an affine transform (RANSAC). Needs a reference image (Open reference...); without one a moved copy is made.'
 'Image registration (phase corr.)',  'Finds the shift between two images from the Fourier phase. Fast, but handles translation only.'
 'Compare: enhancement methods',      'Nine Module 1 results in one picture: histogram, smoothing, sharpening and frequency filters next to the original.'
 'Compare: edge detectors',           'Sobel, Prewitt and Canny edges next to the gray original, with the number of edge pixels in the log.'
 'Compare: segmentation methods',     'Otsu, adaptive threshold, region growing, colour (white) and edges + morphology next to the original.'
 'Compare: geometric transforms',     'Translation, scaling, rotation, shear, affine, forward and reverse mapping and distortion correction next to the original.'
 'Compare: interpolation (zoom)',     'A framed part of the photo enlarged 4 to 6 times with nearest neighbour, bilinear and bicubic interpolation.'
 };
H = containers.Map(c(:, 1), c(:, 2));
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

% ---------------------------- comparison views ----------------------------------------
function [J, info] = cmpEnhance(I, ref)
T = fitTile(I);
if isempty(ref), ref = grayTransform(T, 'gamma', 0.5); else, ref = toDouble(ref); end
J = tileMontage({T, histEqualize(T), histMatch(T, ref), grayTransform(T, 'gamma', 0.5), smoothFilter(T, 'median', 3), ...
                 smoothFilter(T, 'gaussian', 5), sharpenFilter(T, 'laplacian', 1), ...
                 freqFilter(T, 'lowpass', 0.15, 'butterworth'), freqFilter(T, 'highpass', 0.10, 'butterworth')}, [3 3]);
info = 'Nine Module 1 results next to the original (left to right, top to bottom); the name is written in each tile.';
end

function [J, info] = cmpEdges(I, ~)
G = toGray(fitTile(I));
Es = edgeDetect(G, 'sobel');  Ep = edgeDetect(G, 'prewitt');  Ec = edgeDetect(G, 'canny');
J = tileMontage({G, Es, Ep, Ec}, [2 2]);
info = sprintf('Edge pixels: Sobel %d, Prewitt %d, Canny %d', nnz(Es), nnz(Ep), nnz(Ec));
end

function [J, info] = cmpSegment(I, ~)
T = fitTile(I);  G = toGray(T);
[~, Bo] = otsuThreshold(G);
Ba = adaptiveThreshold(G, 31, 0.05, 'dark');
Br = regionGrow(G, round(size(G) / 2), 0.12);
Bc = colorSegment(T, 'HSV', 'white');
Bm = fillHoles(morphOp(edgeDetect(G, 'canny'), 'close', makeSE('disk', 3)));
J = tileMontage({T, Bo, Ba, Br, Bc, Bm}, [2 3]);
info = sprintf('White = segmented foreground. Area: Otsu %.0f %%, adaptive %.0f %%, region growing %.0f %%, colour %.0f %%, edges+closing %.0f %%', ...
               100 * mean(Bo(:)), 100 * mean(Ba(:)), 100 * mean(Br(:)), 100 * mean(Bc(:)), 100 * mean(Bm(:)));
end

function [J, info] = cmpGeom(I, ~)
T = fitTile(I);  [h, w, ~] = size(T);
Ta = affineOpImage(T);
J = tileMontage({T, geometricTransforms(T, 'translate', round(0.08 * w), round(0.06 * h)), geometricTransforms(T, 'scale', 1.4), ...
                 geometricTransforms(T, 'rotate', 15), geometricTransforms(T, 'shear', 0.25, 0), Ta, ...
                 warpImage(T, diag([1.6 1.6 1]), [h w], 'nearest', 'forward'), warpImage(T, diag([1.6 1.6 1]), [h w], 'bilinear', 'reverse'), ...
                 radialDistortion(radialDistortion(T, -0.3, 0, 'apply'), -0.3, 0, 'correct')}, [3 3]);
info = 'Nine Module 3 results next to the original; the name is written in each tile.';
end

function [J, info] = cmpInterp(I, ~)
T = fitTile(I);  [h, w, ~] = size(T);
ch = max(8, round(h / 6));  cw = max(8, round(w / 6));
y0 = max(1, round(h / 2 - ch / 2));  x0 = max(1, round(w / 2 - cw / 2));
crop = T(y0:y0 + ch - 1, x0:x0 + cw - 1, :);
sc = min(h / ch, w / cw);
F = T;  F([y0 y0 + 1 y0 + ch - 2 y0 + ch - 1], x0:x0 + cw - 1, :) = 1;  F(y0:y0 + ch - 1, [x0 x0 + 1 x0 + cw - 2 x0 + cw - 1], :) = 1;
J = tileMontage({F, imResize(crop, sc, 'nearest'), imResize(crop, sc, 'bilinear'), imResize(crop, sc, 'bicubic')}, [2 2]);
info = sprintf('The framed part (%d x %d px) enlarged %.1f times by three interpolation methods.', cw, ch, sc);
end

function J = affineOpImage(T)
a = 10 * pi / 180;
A = 0.9 * [cos(a) sin(a); -sin(a) cos(a)] * [1 0.15; 0 1];
[h, w, ~] = size(T);
c = [(w + 1) / 2; (h + 1) / 2];
J = geometricTransforms(T, 'affine', [A c - A * c]);
end

function T = fitTile(I)
% an RGB copy of the photo, at most 480 pixels on the long side, so that a montage stays small
T = rgb3(I);
sc = min(1, 480 / max(size(T, 1), size(T, 2)));
if sc < 1, T = rgb3(imResize(T, sc, 'bilinear')); end
end

function J = tileMontage(tiles, grid)
% one picture made of grid(1) x grid(2) tiles with a 4-pixel gap (the GUI relies on this layout to write the names)
R = grid(1);  C = grid(2);  g = 4;
h = max(cellfun(@(t) size(t, 1), tiles));  w = max(cellfun(@(t) size(t, 2), tiles));
J = 0.12 * ones(R * h + (R - 1) * g, C * w + (C - 1) * g, 3);
for k = 1:numel(tiles)
    t = rgb3(tiles{k});
    t = t(1:min(h, size(t, 1)), 1:min(w, size(t, 2)), :);
    r = ceil(k / C);  c = mod(k - 1, C) + 1;
    y = (r - 1) * (h + g);  x = (c - 1) * (w + g);
    oy = floor((h - size(t, 1)) / 2);  ox = floor((w - size(t, 2)) / 2);
    J(y + oy + (1:size(t, 1)), x + ox + (1:size(t, 2)), :) = t;
end
end

function T = rgb3(T)
T = min(max(double(T), 0), 1);
if size(T, 3) == 1, T = repmat(T, [1 1 3]); end
end
