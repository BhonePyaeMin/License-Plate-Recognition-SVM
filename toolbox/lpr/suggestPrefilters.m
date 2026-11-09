function [chain, reasons, stats] = suggestPrefilters(I, includeExposure)
%SUGGESTPREFILTERS  Measure a photo and recommend pre-filters (see PREFILTEROPS) for plate recognition.
%   [chain, reasons, stats] = SUGGESTPREFILTERS(I, includeExposure)
%   chain   : struct array (name, p) for APPLYPREFILTERS; empty when the photo looks fine
%   reasons : cell array of sentences, one per recommended filter (what was measured and why)
%   stats   : the measurements: median luminance, 1%..99% range, impulse (salt-and-pepper) share, noise
%             standard deviation, share of saturated pixels, unevenness of the lighting
%   Measurements (on the central part of the photo, at most 640 x 640 pixels, no resizing):
%     impulse share   fraction of pixels that differ from their 3x3 median by more than 0.35: isolated white
%                     or black dots -> MEDIAN filter (3x3, or 5x5 above 8 %)
%     noise sigma     Immerkaer's estimate from the response to the kernel [1 -2 1; -2 4 -2; 1 -2 1], which is
%                     blind to edges and smooth gradients; above 0.025 -> BILATERAL filter (a Gaussian filter
%                     would blur the stroke edges of small characters), above 0.07 a stronger setting
%     exposure        median luminance below 0.25 or above 0.75, and contrast (1%..99% range below 0.45):
%                     RECOGNIZEPLATE repairs these itself (NORMALIZEEXPOSURE: stretch + gamma), so by default
%                     only a remark is made and NO filter is added: a second gamma on top of the automatic
%                     one over-corrects (on test photos darkened by a shading ramp the suggested gamma cost 2 of
%                     16 plates). With includeExposure = true (default false; use it with
%                     recognizePlate(..., 'Exposure', 'off')) a GAMMA that moves the median to 0.5 or a CONTRAST
%                     STRETCHING is added.
%   Reported but not acted on: stats.unevenness (spread of the 8 x 8 block means). It cannot tell a shadow
%   across the plate from scene content (bright sky above a dark road gives 0.5 on an ordinary photo, a
%   synthetic shadow 0.8), so ILLUMINATION CORRECTION is left to the user.
%   Not recommended automatically: blur (a sharpness measure needs a reference, try unsharp masking or the
%   Richardson-Lucy deblurring by hand and watch the result), glare (saturated pixels carry no information),
%   and a tilted or angled plate (that is a geometry problem; see RECTIFYPLATE).

if nargin < 2 || isempty(includeExposure), includeExposure = false; end
I = toDouble(I);
G = toGray(I);
[h, w] = size(G);
r0 = max(1, round(h / 2 - 320)):min(h, round(h / 2 + 319));
c0 = max(1, round(w / 2 - 320)):min(w, round(w / 2 + 319));
C = G(r0, c0);                                              % central part, original pixels

v = sort(G(:));
n = numel(v);
stats.median = v(max(1, round(0.5 * n)));
stats.range = v(max(1, round(0.99 * n))) - v(max(1, round(0.01 * n)));
stats.saturated = mean(G(:) > 0.97);

% impulse noise: dots that differ from the 3x3 median
if min(size(C)) >= 8
    M3 = smoothFilter(C, 'median', 3);
    dev = abs(C - M3);
    stats.impulse = mean(dev(:) > 0.35);
    % noise sigma (Immerkaer), measured on the median-filtered picture when impulses are present
    D = C;  if stats.impulse > 0.005, D = M3; end
    R = spatialFilter(D, [1 -2 1; -2 4 -2; 1 -2 1], 'symmetric');
    [hh, ww] = size(D);
    stats.noise = sqrt(pi / 2) / (6 * max(1, (hh - 2) * (ww - 2))) * sum(sum(abs(R(2:end-1, 2:end-1))));
else
    stats.impulse = 0;  stats.noise = 0;
end

% uneven lighting: block means
by = floor(h / 8);  bx = floor(w / 8);
if by >= 4 && bx >= 4
    bm = zeros(8);
    for i = 1:8
        for j = 1:8
            bm(i, j) = mean(mean(G((i-1)*by+1:i*by, (j-1)*bx+1:j*bx)));
        end
    end
    stats.unevenness = std(bm(:)) / max(mean(bm(:)), 0.05);
else
    stats.unevenness = 0;
end

chain = struct('name', {}, 'p', {});
reasons = {};
if stats.impulse > 0.01
    k = 3;  if stats.impulse > 0.08, k = 5; end
    chain(end+1) = struct('name', 'Median filter', 'p', k); %#ok<AGROW>
    reasons{end+1} = sprintf('%.1f %% of the pixels are isolated white/black dots (salt-and-pepper noise): %d x %d median filter.', 100 * stats.impulse, k, k); %#ok<AGROW>
end
if stats.noise > 0.025
    if stats.noise > 0.07, p = [2, 0.25]; else, p = [1.5, 0.15]; end
    chain(end+1) = struct('name', 'Bilateral filter (edge-preserving)', 'p', p); %#ok<AGROW>
    reasons{end+1} = sprintf('Noise level about %.3f (grey-level std): edge-preserving bilateral filter (sigma_s %.1f, sigma_r %.2f).', stats.noise, p(1), p(2)); %#ok<AGROW>
end
if stats.median < 0.25 || stats.median > 0.75
    g = min(max(log(0.5) / log(min(max(stats.median, 0.02), 0.98)), 0.4), 2.5);
    if includeExposure
        chain(end+1) = struct('name', 'Gamma correction', 'p', g); %#ok<AGROW>
        reasons{end+1} = sprintf('Median luminance %.2f (too %s): gamma %.2f moves it to about 0.5.', stats.median, ternary(stats.median < 0.5, 'dark', 'bright'), g); %#ok<AGROW>
    else
        reasons{end+1} = sprintf('Median luminance %.2f (too %s): the recogniser repairs this itself, so no filter is added (by hand: gamma %.2f or local histogram equalisation).', stats.median, ternary(stats.median < 0.5, 'dark', 'bright'), g); %#ok<AGROW>
    end
elseif stats.range < 0.45
    if includeExposure
        chain(end+1) = struct('name', 'Contrast stretching', 'p', [1 99]); %#ok<AGROW>
        reasons{end+1} = sprintf('Low contrast (1%%..99%% range only %.2f): contrast stretching.', stats.range); %#ok<AGROW>
    else
        reasons{end+1} = sprintf('Low contrast (1%%..99%% range only %.2f): the recogniser stretches it itself, so no filter is added.', stats.range); %#ok<AGROW>
    end
end
if stats.saturated > 0.05
    reasons{end+1} = sprintf('Note: %.0f %% of the pixels are saturated (glare / burnt-out areas): no filter can restore them.', 100 * stats.saturated); %#ok<AGROW>
end
if isempty(chain) && isempty(reasons)
    reasons = {'The photo looks fine (exposure, contrast, noise, lighting): no pre-filter recommended.'};
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
