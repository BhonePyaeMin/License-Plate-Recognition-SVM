function fig = compareEnhancement(I, ref)
%COMPAREENHANCEMENT  Show the original image next to every Module 1 result.
%   fig = COMPAREENHANCEMENT(I) displays histogram equalisation, histogram
%   matching (to REF, or to a gamma-brightened copy of I when REF is omitted),
%   brightness/contrast, smoothing, sharpening and frequency-domain filters.

I = toDouble(I);
if nargin < 2 || isempty(ref), ref = grayTransform(I, 'gamma', 0.6); end
G = I;

fig = figure('Name', 'Module 1 - Image Enhancement', 'Color', 'w', 'Position', [60 60 1200 700]);
items = {
    'Original',                 G
    'Histogram equalisation',   histEqualize(G)
    'Histogram matching',       histMatch(G, ref)
    'Contrast x1.5, +0.05',     grayTransform(G, 'linear', 1.5, 0.05)
    'Gamma 0.5',                grayTransform(G, 'gamma', 0.5)
    'Gaussian smoothing 5x5',   smoothFilter(G, 'gaussian', 5)
    'Laplacian sharpening',     sharpenFilter(G, 'laplacian', 1)
    'Unsharp masking',          sharpenFilter(G, 'unsharp', 1.5)
    'Frequency low-pass',       freqFilter(G, 'lowpass', 0.15, 'butterworth')
    'Frequency high-pass',      freqFilter(G, 'highpass', 0.10, 'butterworth')
    'Frequency band-pass',      freqFilter(G, 'bandpass', [0.05 0.30], 'gaussian')
    'Median 3x3 (after noise)', smoothFilter(addNoise(G, 'saltpepper', 0.08), 'median', 3)
    };
for k = 1:size(items,1)
    ax = subplot(3, 4, k);
    showImage(ax, items{k,2}, items{k,1});
end
end
