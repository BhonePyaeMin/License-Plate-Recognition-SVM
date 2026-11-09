function J = localHistEqualize(I, tiles, clip)
%LOCALHISTEQUALIZE  Adaptive (local) histogram equalisation with contrast limit (Module 1, CLAHE style).
%   J = LOCALHISTEQUALIZE(I, tiles, clip)
%   A global equalisation (HISTEQUALIZE) uses one grey-level mapping for the whole picture; a plate in
%   shadow or in the glare of a head-light needs its own. The image is cut into tiles x tiles blocks, the
%   histogram of every block is clipped (no bin may hold more than clip times the average count; the
%   excess is spread over all bins, which limits the noise amplification in flat areas) and turned into an
%   equalising mapping. A pixel is mapped by the four neighbouring tile mappings and the results are
%   blended bilinearly with the distance to the tile centres, so no block borders appear.
%   tiles default 8, clip default 3. For colour images only the V channel of HSV is processed.

if nargin < 2 || isempty(tiles), tiles = 8; end
if nargin < 3 || isempty(clip), clip = 3; end
I = toDouble(I);
if size(I, 3) == 3
    hsv = rgb2hsv(I);
    hsv(:,:,3) = localHistEqualize(hsv(:,:,3), tiles, clip);
    J = hsv2rgb(hsv);
    return
end
[h, w] = size(I);
tiles = max(1, round(tiles));
ty = min(tiles, h);  tx = min(tiles, w);
nb = 256;
q = min(floor(min(max(I, 0), 1) * nb), nb - 1) + 1;
ye = round(linspace(0, h, ty + 1));  xe = round(linspace(0, w, tx + 1));
maps = zeros(ty, tx, nb);
for i = 1:ty
    for j = 1:tx
        blk = q(ye(i)+1:ye(i+1), xe(j)+1:xe(j+1));
        hst = accumarray(blk(:), 1, [nb 1]);
        lim = max(1, clip * numel(blk) / nb);
        ex = sum(max(hst - lim, 0));
        hst = min(hst, lim) + ex / nb;                       % clip, give the excess back to all bins
        maps(i, j, :) = cumsum(hst) / sum(hst);
    end
end
cy = (ye(1:end-1) + ye(2:end)) / 2 + 0.5;                    % tile centres (pixel coordinates)
cx = (xe(1:end-1) + xe(2:end)) / 2 + 0.5;
py = tilePosition(cy, (1:h).');  px = tilePosition(cx, (1:w));
i0 = floor(py);  i1 = min(i0 + 1, ty);  fy = py - i0;           % h x 1
j0 = floor(px);  j1 = min(j0 + 1, tx);  fx = px - j0;           % 1 x w
sz = [ty tx nb];
v00 = maps(sub2ind(sz, repmat(i0, 1, w), repmat(j0, h, 1), q));
v01 = maps(sub2ind(sz, repmat(i0, 1, w), repmat(j1, h, 1), q));
v10 = maps(sub2ind(sz, repmat(i1, 1, w), repmat(j0, h, 1), q));
v11 = maps(sub2ind(sz, repmat(i1, 1, w), repmat(j1, h, 1), q));
J = (1 - fy) .* ((1 - fx) .* v00 + fx .* v01) + fy .* ((1 - fx) .* v10 + fx .* v11);
J = min(max(J, 0), 1);
end

function pos = tilePosition(c, p)
% continuous tile index in [1, n] of the pixel coordinates p, from the tile centres c (end values are kept
% outside the first and last centre)
n = numel(c);
pos = ones(size(p));
if n == 1, return; end
for k = 1:n-1
    m = p >= c(k) & p < c(k+1);
    pos(m) = k + (p(m) - c(k)) / (c(k+1) - c(k));
end
pos(p >= c(end)) = n;
end
