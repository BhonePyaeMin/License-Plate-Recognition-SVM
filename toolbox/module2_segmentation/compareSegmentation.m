function fig = compareSegmentation(I, seed)
%COMPARESEGMENTATION  Compare thresholding, region growing, colour and edge+morphology segmentation.
%   fig = COMPARESEGMENTATION(I, seed) - seed = [row col] for region growing
%   (default: image centre).

I = toDouble(I);
G = toGray(I);
if nargin < 2 || isempty(seed), seed = round(size(G) / 2); end

[level, Bo] = otsuThreshold(G);
Ba = adaptiveThreshold(G, 31, 0.05, 'bright');
Br = regionGrow(G, seed, 0.12);
if size(I,3) == 3, Bc = colorSegment(I, 'HSV', 'white'); else, Bc = false(size(G)); end
E  = edgeDetect(G, 'canny');
Bm = fillHoles(morphOp(E, 'close', makeSE('disk', 3)));
Bs = morphOp(morphOp(Bm, 'open', makeSE('disk', 2)), 'erode', makeSE('disk', 1));

fig = figure('Name', 'Module 2 - Segmentation comparison', 'Color', 'w', 'Position', [60 60 1200 650]);
items = {
    'Original', G
    sprintf('Otsu threshold (t = %.2f)', level), Bo
    'Adaptive threshold', Ba
    'Region growing', Br
    'Colour segmentation (white, HSV)', Bc
    'Canny edges', E
    'Edges + closing + fill holes', Bm
    'Shape cleaning (open + erode)', Bs
    };
for k = 1:size(items,1)
    showImage(subplot(2,4,k), items{k,2}, items{k,1});
end
hold(subplot(2,4,4), 'on');
plot(subplot(2,4,4), seed(2), seed(1), 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);
end
