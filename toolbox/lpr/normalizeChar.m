function N = normalizeChar(ink, outSize, fill)
%NORMALIZECHAR  Crop a binary character to its bounding box and fit it into a square canvas.
%   N = NORMALIZECHAR(ink, outSize, fill)
%   ink     : logical/double image, character pixels = 1
%   outSize : side of the output canvas (default 32)
%   fill    : fraction of the canvas the longer glyph side occupies (default 0.8)
%   The aspect ratio is preserved and the glyph is centred, so the SVM sees the
%   same geometry for training characters and for characters cut out of plates.

if nargin < 2 || isempty(outSize), outSize = 32; end
if nargin < 3 || isempty(fill),    fill = 0.8; end
ink = double(ink);
mask = ink > 0.5;
rr = find(any(mask, 2));  cc = find(any(mask, 1));
N = zeros(outSize);
if isempty(rr), return; end
g = ink(rr(1):rr(end), cc(1):cc(end));
[h, w] = size(g);
s = fill * outSize / max(h, w);
nh = max(1, min(outSize, round(h * s)));
nw = max(1, min(outSize, round(w * s)));
g = imResize(g, [nh nw], 'bilinear');
r0 = floor((outSize - nh) / 2);  c0 = floor((outSize - nw) / 2);
N(r0 + (1:nh), c0 + (1:nw)) = g;
end
