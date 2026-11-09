function f = plateFeatures(crop)
%PLATEFEATURES  HOG descriptor of a candidate region, for the plate / not-plate SVM.
%   f = PLATEFEATURES(crop) resizes the (colour or gray) crop to 32 x 128 pixels,
%   stretches its contrast and returns a 1 x 1620 HOG vector (8 x 8 cells, 9 bins).
%   A licence plate crop has a typical texture: a row of vertical strokes with a
%   regular spacing inside a bright rectangle - exactly what HOG encodes.

G = toGray(crop);
G = imResize(G, [32 128], 'bilinear');
lo = min(G(:));  hi = max(G(:));
G = (G - lo) / max(hi - lo, 0.05);
f = hogFeatures(G, 8, 9);
end
