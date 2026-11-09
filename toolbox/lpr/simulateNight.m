function J = simulateNight(I, level, seed)
%SIMULATENIGHT  Make a daylight photo look like a night photo (for testing; NOT a real night photo).
%   J = SIMULATENIGHT(I, level, seed)
%   level 'dark'  : very dark, median luminance about 0.1 (NORMALIZEEXPOSURE repairs it)
%         'lit'   : a lit night street, median luminance about 0.25-0.35 (above the repair
%                   threshold, so the photo is NOT repaired); warm orange cast
%   Steps: gamma and darkening, colour cast of street lamps, two soft light glows (one red
%   tail-light like, one white head-light like) placed in the lower half, sensor noise.
%   seed makes the result repeatable. The glows and the noise are crude: this only checks how
%   the recogniser copes with dark, noisy, glowing images; real night photos are harder.
if nargin < 3, seed = 1; end
if nargin < 2, level = 'lit'; end
I = toDouble(I);
if size(I, 3) == 1, I = repmat(I, [1 1 3]); end            % grey input: the lamp colours need three channels
st = rng;  rng(seed);
[h, w, ~] = size(I);
switch lower(level)
    case 'dark', g = 2.4;  k = 0.55;  cast = [1.00 0.90 0.80];  noise = 0.04;
    otherwise,   g = 1.2;  k = 1.00;  cast = [1.00 0.90 0.72];  noise = 0.03;
end
J = k * I .^ g;
for ch = 1:3, J(:,:,ch) = J(:,:,ch) * cast(ch); end
[x, y] = meshgrid(1:w, 1:h);
cols = {[1 0.15 0.1], [1 1 0.9]};
for q = 1:2
    cx = rand * w;  cy = (0.5 + 0.4 * rand) * h;  r = (0.05 + 0.08 * rand) * w;
    m = exp(-(((x - cx) / r).^2 + ((y - cy) / (0.6 * r)).^2));
    for ch = 1:3, J(:,:,ch) = J(:,:,ch) + 0.6 * cols{q}(ch) * m; end
end
J = min(max(J + noise * randn(size(J)), 0), 1);
rng(st);
end
