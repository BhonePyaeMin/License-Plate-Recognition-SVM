function [cand, mined] = slidingPlateCandidates(img, pm, varargin)
%SLIDINGPLATECANDIDATES  Scan the whole photo with the plate SVM (sliding window, image pyramid).
%   cand = SLIDINGPLATECANDIDATES(img, pm, 'Name', value, ...)
%   img : RGB or gray photo, pm : plate SVM from TRAINPLATEMODEL (its decision value is
%   the score of every window).
%   A window of 128 x 32 pixels (plate shape, 4:1) is slid over the photo at several
%   scales. The HOG descriptor is computed once per scale for the whole image (cell
%   histograms and block normalisation), and the descriptor of every window is the
%   concatenation of its 3 x 15 blocks - identical in layout to PLATEFEATURES, so the
%   SVM trained on candidate regions can score the windows directly.
%   Options: 'Widths'   plate widths to look for, in pixels of the working image
%                       (default [90 122 165 225 305 415])
%            'WorkWidth' the photo is resized to this width first (default 960; photos narrower
%                       than half of it are enlarged only 2x)
%            'Stride'   window step in cells of 8 pixels (default 2 horizontally, 1 vertically
%                       for the larger scales)
%            'MinScore' windows with a lower SVM score are dropped (default -0.3)
%            'MaxOut'   at most this many windows after non-maximum suppression (default 30)
%            'GT'       true plate box [x y w h] of the photo: mining mode for training. The second
%                       output then holds the descriptors of windows that cover the plate (IoU >= 0.6,
%                       up to 'NPos' best) and of the highest-scoring windows that do not (IoU < 0.3,
%                       up to 'NNeg'): positives and hard negatives for the plate SVM
%   cand is a struct array with the fields box ([x y w h] in the photo), score.

p = inputParser;
p.addParameter('Widths', [90 122 165 225 305 415]);
p.addParameter('WorkWidth', 960);
p.addParameter('MinScore', -0.3);
p.addParameter('MaxOut', 30);
p.addParameter('GT', []);
p.addParameter('NPos', 12);
p.addParameter('NNeg', 80);
p.parse(varargin{:});
o = p.Results;

img = toDouble(img);
[H0, W0, ~] = size(img);
k0 = min(2, o.WorkWidth / W0);                              % large photos are shrunk, small ones enlarged (at most 2x)
G0 = toGray(img);
if k0 ~= 1, G0 = imResize(G0, k0, 'bilinear'); end
[Hw, Ww] = size(G0);

sv = pm.svm.SV;  coef = pm.svm.coef;  b = pm.svm.b;  gam = pm.svm.kernel.gamma;
sv2 = sum(sv.^2, 2).';
box = zeros(0, 4);  sc = zeros(0, 1);
mined = struct('Xpos', zeros(0, 1620), 'ipos', zeros(0, 1), 'Xneg', zeros(0, 1620), 'sneg', zeros(0, 1));
for W = o.Widths
    s = 128 / W;                                            % scale: plate of width W -> 128 px wide window
    Gs = imResize(G0, s, 'bilinear');
    [h, w] = size(Gs);
    if h < 40 || w < 136, continue; end
    BV = denseBlocks(Gs);                                   % nBy x nBx x 36 normalised blocks
    [nBy, nBx, ~] = size(BV);
    rr = 1:2:(nBy - 2);  cc = 1:2:(nBx - 14);               % window origins in cells
    if isempty(rr) || isempty(cc), continue; end
    [R, C] = meshgrid(rr, cc);  R = R(:);  C = C(:);
    n = numel(R);
    scores = zeros(n, 1);
    slice = reshape(BV, [], 36);                            % row = block (column-major over r,c)
    for i0 = 1:2500:n                                       % batches keep the memory small
        ii = i0:min(n, i0 + 2499);
        F = zeros(numel(ii), 1620);
        for dr = 0:2
            for dc = 0:14
                lin = sub2ind([nBy nBx], R(ii) + dr, C(ii) + dc);
                F(:, (dr*15 + dc)*36 + (1:36)) = slice(lin, :);
            end
        end
        D2 = sum(F.^2, 2) + sv2 - 2 * (F * sv.');
        scores(ii) = exp(-gam * max(D2, 0)) * coef + b;
        if ~isempty(o.GT)                                   % mining: windows that fit / miss the true plate
            wx = ((C(ii) - 1) * 8) / s / k0 + 1;  wy = ((R(ii) - 1) * 8) / s / k0 + 1;
            ov = boxOverlap([wx, wy, repmat(128 / s / k0, numel(ii), 1), repmat(32 / s / k0, numel(ii), 1)], o.GT);
            hit = ov >= 0.6;
            mined.Xpos = [mined.Xpos; F(hit, :)];  mined.ipos = [mined.ipos; ov(hit)];
            miss = find(ov < 0.3 & scores(ii) >= o.MinScore);
            mined.Xneg = [mined.Xneg; F(miss, :)];  mined.sneg = [mined.sneg; scores(ii(miss))];
        end
    end
    keep = scores >= o.MinScore;
    if ~any(keep), continue; end
    x = ((C(keep) - 1) * 8) / s / k0 + 1;                   % back to coordinates of the photo
    y = ((R(keep) - 1) * 8) / s / k0 + 1;
    bw = 128 / s / k0;  bh = 32 / s / k0;
    box = [box; x, y, repmat(bw, nnz(keep), 1), repmat(bh, nnz(keep), 1)]; %#ok<AGROW>
    sc = [sc; scores(keep)]; %#ok<AGROW>
end

if ~isempty(o.GT)                                           % keep the best-fitting positives and the hardest negatives
    [~, ip] = sort(mined.ipos, 'descend');  ip = ip(1:min(o.NPos, numel(ip)));
    [~, in] = sort(mined.sneg, 'descend');  in = in(1:min(o.NNeg, numel(in)));
    mined.Xpos = mined.Xpos(ip, :);  mined.ipos = mined.ipos(ip);
    mined.Xneg = mined.Xneg(in, :);  mined.sneg = mined.sneg(in);
end

cand = struct('box', {}, 'score', {});
[~, order] = sort(sc, 'descend');
used = false(numel(order), 1);
for ii = 1:numel(order)
    i = order(ii);
    if used(i), continue; end
    bi = box(i, :);
    box(i, 1) = max(1, bi(1));  box(i, 2) = max(1, bi(2));
    bi = box(i, :);
    cand(end+1) = struct('box', bi, 'score', sc(i)); %#ok<AGROW>
    for jj = ii+1:numel(order)                             % suppress overlapping windows
        j = order(jj);
        if ~used(j) && iou(bi, box(j, :)) > 0.3, used(j) = true; end
    end
    if numel(cand) >= o.MaxOut, break; end
end
% keep boxes inside the photo
for i = 1:numel(cand)
    b2 = cand(i).box;
    b2(3) = min(b2(3), W0 - b2(1) + 1);  b2(4) = min(b2(4), H0 - b2(2) + 1);
    cand(i).box = b2;
end
end

% =========================================================================================
function BV = denseBlocks(G)
% Block-normalised HOG of the whole image: cells of 8x8 pixels, 9 unsigned orientation bins
% with linear interpolation, blocks of 2x2 cells with L2-Hys (same recipe as HOGFEATURES).
[h, w] = size(G);
Gx = zeros(h, w);  Gy = zeros(h, w);
Gx(:, 2:end-1) = G(:, 3:end) - G(:, 1:end-2);
Gy(2:end-1, :) = G(3:end, :) - G(1:end-2, :);
mag = hypot(Gx, Gy);
ang = mod(atan2(Gy, Gx), pi);
nCy = floor(h / 8);  nCx = floor(w / 8);
pos = ang / pi * 9 - 0.5;
b0 = floor(pos);  frac = pos - b0;
bin0 = mod(b0, 9) + 1;  bin1 = mod(b0 + 1, 9) + 1;
[X, Y] = meshgrid(1:w, 1:h);
cy = ceil(Y / 8);  cx = ceil(X / 8);
valid = cy <= nCy & cx <= nCx;
cy = cy(valid);  cx = cx(valid);  m = mag(valid);  fr = frac(valid);
bin0 = bin0(valid);  bin1 = bin1(valid);
Hc = accumarray([cy cx bin0], m .* (1 - fr), [nCy nCx 9]) + accumarray([cy cx bin1], m .* fr, [nCy nCx 9]);
nBy = nCy - 1;  nBx = nCx - 1;
BV = zeros(nBy, nBx, 36);
for r = 1:nBy
    for c = 1:nBx
        blk = Hc(r:r+1, c:c+1, :);  v = blk(:);
        v = v / sqrt(sum(v.^2) + 1e-6);  v = min(v, 0.2);  v = v / sqrt(sum(v.^2) + 1e-6);
        BV(r, c, :) = v;
    end
end
end

function v = iou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end

function v = boxOverlap(A, g)
% IoU of every row of A ([x y w h]) with the box g
x1 = max(A(:,1), g(1));  y1 = max(A(:,2), g(2));
x2 = min(A(:,1) + A(:,3), g(1) + g(3));  y2 = min(A(:,2) + A(:,4), g(2) + g(4));
inter = max(0, x2 - x1) .* max(0, y2 - y1);
v = inter ./ (A(:,3) .* A(:,4) + g(3) * g(4) - inter);
end
