function [P, box] = tightenPlate(plate)
%TIGHTENPLATE  Cut the surroundings (dark bumper, bright border, shadow) off a loose plate crop.
%   [P, box] = TIGHTENPLATE(plate) returns the part of the crop that has the colour of the plate background
%   and the box [x y w h] of that part in the crop. The background colour is the median colour of the middle
%   of the crop (the characters cover less than half of it); pixels close to that colour form the plate, the
%   characters are holes in it, so the bounding box of the largest such region is the plate without its surroundings;
%   a margin of the plate colour is added so that the characters do not touch the border of the new crop.
%   A crop in which no plate-sized region of that colour is found is returned unchanged.
%   Why: on a plate with a dark strip above it and a bright strip below it (UK plates on a silver car) the
%   characters touch those strips after binarisation and no character can be cut out; inside the plate they can.

plate = toDouble(plate);
[H, W, C] = size(plate);
P = plate;  box = [1 1 W H];
if H < 12 || W < 30, return; end
r = max(1, round(0.3 * H)):round(0.7 * H);  c = max(1, round(0.15 * W)):round(0.85 * W);
mid = reshape(plate(r, c, :), [], C);
g = mean(mid, 2);                                                          % two clusters (background / characters): the larger one is the plate
lev = otsuThreshold(g);
hi = g >= lev;
if mean(hi) < 0.5, hi = ~hi; end
mu = median(mid(hi, :), 1);
d = sqrt(sum((plate - reshape(mu, 1, 1, C)) .^ 2, 3));
tau = 0.12 + 0.06 * (C == 3);
mask = d < tau;
mask = morphOp(mask, 'close', makeSE('rect', [3, 3]));
mask = fillHoles(mask);
[L, n] = labelComponents(mask, 8);
if n == 0, return; end
props = componentProps(L, n);
[~, k] = max(props.Area);
bb = props.BoundingBox(k, :);
if bb(3) < 0.5 * W || bb(4) < 0.35 * H || bb(3) * bb(4) < 0.25 * W * H, return; end
x0 = max(1, bb(1) + 1);  y0 = max(1, bb(2) + 1);
x1 = min(W, bb(1) + bb(3) - 2);  y1 = min(H, bb(2) + bb(4) - 2);
if x1 - x0 < 20 || y1 - y0 < 8, return; end
inner = plate(y0:y1, x0:x1, :);
py = round(0.2 * size(inner, 1));  px = round(0.1 * size(inner, 1));       % a margin of plate colour: characters that fill the plate must not touch the border
inPlate = repmat(L == k, [1 1 C]);                                          % the margin has the colour of the plate background itself
bg = median(reshape(plate(inPlate), [], C), 1);
P = repmat(reshape(bg, 1, 1, C), size(inner, 1) + 2 * py, size(inner, 2) + 2 * px);
P(py + 1:py + size(inner, 1), px + 1:px + size(inner, 2), :) = inner;
box = [x0 - px, y0 - py, size(P, 2), size(P, 1)];
end
