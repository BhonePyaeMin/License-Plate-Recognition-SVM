function [rect, ok, info] = rectifyPlate(crop, varargin)
%RECTIFYPLATE  Straighten a plate photographed at an angle (perspective correction, Module 3).
%   [rect, ok, info] = RECTIFYPLATE(crop, 'Name', value, ...)
%   crop : RGB or gray image that contains the plate (a candidate region of the photo).
%   rect : the plate warped to an upright rectangle of OutSize pixels ([] if ok is false).
%   ok   : true when a plate-like quadrilateral was found (see below).
%   info : quad (4x2, corners TL TR BR BL in crop coordinates), H (3x3), aspect, fill, tilt, slant,
%          keystone, distortion (how far the quadrilateral is from an upright rectangle), reason,
%          candidates (all accepted outlines with their step contrast), rejected (why the others failed).
%   Steps
%     1. grey image, Otsu threshold; the plate is the largest bright (or dark) blob. Holes are filled so
%        that the characters belong to the blob (both polarities are tried);
%     2. the four corners are the extreme points of the blob along the diagonals: TL = min(x+y),
%        BR = max(x+y), TR = max(x-y), BL = min(x-y) (these points lie on the convex hull);
%     3. the quadrilateral is accepted only if it looks like a plate: convex, 15-98 % of the crop, the blob
%        fills 80-110 % of it, width/height between 1.8 and 7.5, opposite sides within a factor 2, top
%        edge within 45 degrees of horizontal;
%     4. HOMOGRAPHY (DLT) maps the quadrilateral to an inner rectangle of OutSize, and WARPIMAGE
%        (reverse mapping, bilinear) resamples the plate.
%   Options: 'OutSize' [rows cols] of rect. Default [] = automatic: 80 rows and 80 * aspect columns, with the
%                      aspect of the quadrilateral limited to 2..6 (about 240 x 80 for a 3:1 plate). A fixed
%                      [80 240] squeezes a 4.6:1 plate by a third, which makes O look like 0.
%            'MaxDim'  longest side of the working image used to find the corners (default 240)
%            'MinArea' smallest accepted quadrilateral area as a fraction of the crop (default 0.15)
%   distortion = max of the in-plane tilt (degrees), the slant of the side edges relative to the tilt
%   (degrees) and the keystone effect (100 * |log(top/bottom)| and the same for the sides): about 0 for an
%   upright rectangle, large for a plate seen from the side.

p = inputParser;
p.addParameter('OutSize', []);
p.addParameter('MaxDim', 240);
p.addParameter('MinArea', 0.15);
p.parse(varargin{:});
o = p.Results;

rect = [];  ok = false;
info = struct('quad', [], 'H', [], 'aspect', NaN, 'fill', NaN, 'tilt', NaN, 'slant', NaN, ...
              'keystone', NaN, 'distortion', NaN, 'reason', 'no plate-like blob', 'candidates', [], 'rejected', {{}});
crop = toDouble(crop);
[h0, w0, ~] = size(crop);
if h0 < 12 || w0 < 24, info.reason = 'crop too small';  return; end
k = min(1, o.MaxDim / max(h0, w0));
G = toGray(crop);
if k < 1, G = imResize(G, k, 'bilinear'); end
[h, w] = size(G);
% three thresholds: Otsu of the whole crop, and Otsu of the brighter and of the darker part (a plate between
% grey surroundings and its own characters has three grey levels; the first threshold may split the wrong pair)
l1 = otsuThreshold(G);
up = G(G > l1);  lo = G(G <= l1);
levels = l1;
if numel(up) > 50, levels(end+1) = otsuThreshold(up); end
if numel(lo) > 50, levels(end+1) = otsuThreshold(lo); end

cands = struct('quad', {}, 'qi', {});
for level = levels
    for lightPlate = [true false]
        if lightPlate, BW = G >= level; else, BW = G < level; end
        [L, n] = labelComponents(BW, 8);                            % raw blobs: the corners do not depend on holes
        if n == 0, continue; end
        pr = componentProps(L, n);
        [~, order] = sort(pr.Area, 'descend');
        for q = order(1:min(3, n)).'
            if pr.Area(q) < 0.4 * o.MinArea * h * w, break; end    % (a plate blob has holes: its characters)
            [r, c] = find(L == q);
            quad = [c(argmin(c + r)), r(argmin(c + r)); ...         % TL
                    c(argmax(c - r)), r(argmax(c - r)); ...         % TR
                    c(argmax(c + r)), r(argmax(c + r)); ...         % BR
                    c(argmin(c - r)), r(argmin(c - r))];            % BL
            blobArea = nnz(fillHoles(L == q));                      % area with the characters filled in
            [good, qi, why] = checkQuad(quad, blobArea, h, w, o.MinArea);
            if good, cands(end+1) = struct('quad', quad, 'qi', qi); %#ok<AGROW>
            else, info.rejected{end+1} = why; end                       %#ok<AGROW>
        end
    end
end
if isempty(cands), return; end
% rate every candidate by the step between the band just inside and the ring just outside its outline: the real
% plate edge has a clear step; the grey surroundings (their ring is outside the crop) and a boundary that cuts
% through the plate or through a character have none. Without any step take the largest well-filling blob.
[X, Y] = meshgrid(1:w, 1:h);
se = makeSE('rect', [9 9]);
ct = zeros(1, numel(cands));
for i = 1:numel(cands)
    qd = cands(i).quad;
    M = inpolygon(X, Y, qd(:, 1), qd(:, 2));
    inner = M & ~morphOp(M, 'erode', se);
    ring = morphOp(M, 'dilate', se) & ~M;
    if nnz(ring) >= 30 && nnz(inner) >= 30, ct(i) = abs(median(G(inner)) - median(G(ring))); end
end
fills = arrayfun(@(c) c.qi.fill, cands);  areas = arrayfun(@(c) c.qi.area, cands);
info.candidates = struct('quad', {cands.quad}, 'step', num2cell(ct), 'fill', num2cell(fills), 'area', num2cell(areas));
if max(ct) >= 0.08
    [~, i] = max(ct);
else
    good = find(fills >= 0.88);
    if isempty(good), [~, i] = max(fills); else, [~, j] = max(areas(good)); i = good(j); end
end
info = mergeInfo(info, cands(i).qi);  info.quad = cands(i).quad;  info.reason = '';

quad = info.quad / k;                                           % back to the pixel grid of the crop
if isempty(o.OutSize)
    Hh = 80;  Wd = round(80 * min(max(info.aspect, 2), 6));
else
    Hh = o.OutSize(1);  Wd = o.OutSize(2);
end
mx = 0.03 * Wd;  my = 0.06 * Hh;                                % a little margin around the plate
dst = [1 + mx, 1 + my; Wd - mx, 1 + my; Wd - mx, Hh - my; 1 + mx, Hh - my];
[H, err] = homography(quad, dst);
if err > 1e-6 || any(~isfinite(H(:)))
    info.reason = 'homography failed';  info.quad = [];  return
end
fillVal = median([crop(1, :, 1), crop(end, :, 1), crop(:, 1, 1).', crop(:, end, 1).']);
rect = warpImage(crop, H, [Hh Wd], 'bilinear', 'reverse', fillVal);
info.H = H;  info.quad = quad;
ok = true;
end

% ------------------------------------------------------------------------------------------
function i = argmin(v)
% index of the minimum; ties are broken by taking the middle one (a straight edge gives a run of ties)
m = find(v == min(v));
i = m(ceil(numel(m) / 2));
end

function i = argmax(v)
m = find(v == max(v));
i = m(ceil(numel(m) / 2));
end

function [good, qi, why] = checkQuad(quad, blobArea, h, w, minArea)
% is the quadrilateral (TL TR BR BL) a plausible plate outline? qi holds its measures
good = false;  why = '';
qi = struct('area', 0, 'aspect', NaN, 'fill', NaN, 'tilt', NaN, 'slant', NaN, 'keystone', NaN, 'distortion', NaN);
x = quad(:, 1);  y = quad(:, 2);
qi.area = 0.5 * abs(sum(x .* y([2 3 4 1]) - x([2 3 4 1]) .* y));
if qi.area < minArea * h * w || qi.area > 0.98 * h * w, why = sprintf('area %.2f of the crop', qi.area / (h * w));  return; end
e = [x([2 3 4 1]) - x, y([2 3 4 1]) - y];                       % edge vectors TL->TR->BR->BL->TL
cr = e(:, 1) .* e([2 3 4 1], 2) - e(:, 2) .* e([2 3 4 1], 1);   % cross products of consecutive edges
if ~(all(cr > 0) || all(cr < 0)), why = 'not convex';  return; end    % must be convex
qi.fill = blobArea / qi.area;
if qi.fill < 0.8 || qi.fill > 1.1, why = sprintf('blob fills %.2f of its quadrilateral', qi.fill);  return; end
top = hypot(e(1, 1), e(1, 2));  right = hypot(e(2, 1), e(2, 2));
bottom = hypot(e(3, 1), e(3, 2));  left = hypot(e(4, 1), e(4, 2));
if min([top right bottom left]) < 4, why = 'degenerate side';  return; end
qi.aspect = mean([top bottom]) / mean([left right]);
if qi.aspect < 1.8 || qi.aspect > 7.5, why = sprintf('aspect %.1f', qi.aspect);  return; end
if max(top / bottom, bottom / top) > 2 || max(left / right, right / left) > 2, why = 'opposite sides differ by more than 2x';  return; end
angTop = atan2d(e(1, 2), e(1, 1));                              % degrees, y points down
angBot = atan2d(-e(3, 2), -e(3, 1));
if abs(angTop) > 45 || abs(angBot) > 45, why = 'top edge steeper than 45 degrees';  return; end
angRight = atan2d(e(2, 1), e(2, 2));                            % deviation of the side edges from vertical
angLeft = atan2d(-e(4, 1), -e(4, 2));
qi.tilt = mean([angTop angBot]);
qi.slant = mean([angLeft angRight]) + qi.tilt;                  % a pure rotation tilts the sides by -tilt: slant 0
qi.keystone = 100 * max(abs(log(top / bottom)), abs(log(left / right)));
qi.distortion = max([abs(qi.tilt), abs(qi.slant), qi.keystone]);
good = true;
end

function info = mergeInfo(info, qi)
f = fieldnames(qi);
for i = 1:numel(f)
    if isfield(info, f{i}), info.(f{i}) = qi.(f{i}); end
end
end
