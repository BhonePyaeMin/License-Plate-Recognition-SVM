function [chars, boxes, dbg] = segmentChars(plateImg, varargin)
%SEGMENTCHARS  Cut a plate image into normalised character images.
%   [chars, boxes, dbg] = SEGMENTCHARS(plateImg, 'Name', value, ...)
%   chars : cell array of 32x32 character images (left to right)
%   boxes : n x 4 bounding boxes [x y w h] in the resized plate (height 100)
%   dbg   : struct with the resized/deskewed plate, the binary image and labels
%   Options: 'Height'   working plate height in pixels (default 100)
%            'Polarity' 'auto' (default) | 'dark' | 'bright' (character colour)
%            'Strategies' binarisation methods to try, any of {'otsu','adaptive'}
%                       (default {'otsu'}; on the synthetic test set adding the local
%                       adaptive threshold lowered exact-plate accuracy by ~6 points;
%                       it has not been tested on real photos with strong shadows)
%            'SearchAngle' true: try tilts of -20..+20 degrees (step 4) and keep the one that
%                       gives the most plate-like row of characters (for tight plate photos,
%                       where the plate frame disturbs the usual tilt estimate; default false)
%            'Trim'     fraction of the plate height cut off every side before segmenting
%                       (default 0). In a tight plate photo it removes the plate frame
%                       that otherwise touches and swallows the first/last character.
%            'Interp'   interpolation used to resize the plate: 'bilinear' (default) |
%                       'bicubic' (sharper when a small plate is enlarged)
%            'Smooth'   false (default) | true: 3x3 Gaussian smoothing after resizing.
%                       Off by default: on real photos, where plates are small and
%                       already blurry, smoothing lowered the character accuracy
%            'HeightRange' accepted character height relative to the typical one
%                       (default [0.65 1.6]; Q has a tail, I and 1 are thin)
%            'Channel'  grey image used for a colour plate: 'gray' (default) | 'min' | 'max' |
%                       'red' | 'green' | 'blue'. 'min' (darkest channel) separates black
%                       characters from a yellow or coloured background better than luminance.
%            'LevelRegion' 'all' (default) | 'center': the Otsu level is computed from the
%                       middle of the crop only, so that a bright car body or a dark bumper
%                       around the plate does not decide the threshold
%            'SearchShear' true: after the tilt search, try horizontal shears (slanted characters, the
%                       plate seen from the side) and keep the one with the most plate-like row
%            'ShearRange' largest shear tried (default 0.6, step 0.15)
%            'AngleRange' largest tilt (degrees) tried by 'SearchAngle' (default 20)
%            'Levels'   multipliers of the Otsu level that are tried (default 1). A lower or
%                       higher level separates characters that touch each other or the plate frame.
%            'Select'   how the best binarisation is chosen: 'count' (default: most characters)
%                       | 'row' (most plate-like row, see PLATEROWSCORE)
%            'TopHat'   0 (default) | fraction of the plate height: a morphological top-hat with a disc of this radius
%                       (white top-hat for bright characters, black top-hat for dark ones) removes blobs much
%                       larger than a stroke, e.g. the glare of the lamps above a night plate, which otherwise
%                       fuses with the characters (0.18 is used by the rescue variants)
%            'Tighten'  true: the crop is first cut down to the region that has the colour of the plate background (TIGHTENPLATE), so
%                       that the strips of bumper or border around the plate do not touch the characters (default false)
%            'Open'     0 (default) | size in pixels (of the plate resized to 100 rows): the binary image is opened with a square of this
%                       size, which removes thin bridges such as the shadow strip along the top edge of a plate that joins all characters
%            'Rules'    true: runs of foreground pixels longer than 1.3 plate heights (a shadow strip or frame line along the plate, which joins
%                       every character) are erased before the characters are cut out (default false)
%            'Flat'     true: the background level of every row is subtracted before the threshold (dark strip across a plate, e.g. the shadow
%                       under a boot lid) (default false)
%            'Proj'     true: the characters are cut out with projection profiles instead of connected components, so that a strip that
%                       joins them does not matter (default false)
%            'Split'    true: a component that is much wider than tall (two to five bold or blurred characters
%                       that touch, as in small night plates: MH14 TCF 735 -> three blobs) is cut at the
%                       minima of its vertical projection before the characters are selected (default false)
%            'FixMerged' true: a character of the chosen row that is at least 1.6 times as wide as the others (and as wide as 0.65
%                       of the character height) is two characters that touch (F + H of FHM 5505, "20" and "EE" of MH 20 EE 0943);
%                       it is cut at the lowest column of its vertical projection and the row is chosen again (default false)
%
%   Steps: resize and smooth -> Otsu binarisation (characters = foreground)
%   -> connected components -> keep the group of components that look like
%   characters (similar height, roughly square, lying on a straight line fitted
%   robustly through their centroids) -> correct the plate's rotation -> repeat
%   -> normalise every character (crop, scale to 32x32).

p = inputParser;
p.addParameter('Height', 100);
p.addParameter('Polarity', 'auto');
p.addParameter('Strategies', {'otsu'});
p.addParameter('HeightRange', [0.65 1.6]);
p.addParameter('Interp', 'bilinear');
p.addParameter('Smooth', false);
p.addParameter('Trim', 0);
p.addParameter('SearchAngle', false);
p.addParameter('Channel', 'gray');
p.addParameter('LevelRegion', 'all');
p.addParameter('SearchShear', false);
p.addParameter('ShearRange', 0.6);
p.addParameter('AngleRange', 20);
p.addParameter('Levels', 1);
p.addParameter('Select', 'count');
p.addParameter('Split', false);
p.addParameter('TopHat', 0);
p.addParameter('Tighten', false);
p.addParameter('Open', 0);
p.addParameter('Rules', false);
p.addParameter('Flat', false);
p.addParameter('Proj', false);
p.addParameter('FixMerged', false);
p.parse(varargin{:});
o = p.Results;
o.Fix = o.FixMerged;

if o.Tighten, plateImg = tightenPlate(plateImg); end         % cut the dark / bright strips around the plate off
G = channelImage(plateImg, o.Channel);
G = imResize(G, o.Height / size(G, 1), o.Interp);
if o.Smooth, G = smoothFilter(G, 'gaussian', 3, 0.8); end
if o.Trim > 0                                              % cut the plate frame / margin off before segmenting
    tr = round(o.Trim * size(G, 1));  tc = round(o.Trim * size(G, 1));
    G = G(1 + tr:end - tr, 1 + tc:end - tc);
end

if o.SearchAngle                                          % tight plate photo: find the tilt by trying angles
    bestScore = -1;  bestA = 0;
    for a = -o.AngleRange:4:o.AngleRange
        Ga = rotateFill(G, a);
        rs = bestPolarity(Ga, o.Polarity, o.Strategies, o.HeightRange, o.LevelRegion, o.Levels, o.Select, o.Split, o.Open, o.Rules, o.Flat, o.Proj, o.Fix);
        sc = 0;
        if rs.n >= 3, sc = plateRowScore(rs.props.BoundingBox(rs.keep, :)) + 0.02 * rs.n; end
        if sc > bestScore + 1e-9 || (abs(sc - bestScore) <= 1e-9 && abs(a) < abs(bestA)), bestScore = sc;  bestA = a; end
    end
    if bestA ~= 0, G = rotateFill(G, bestA); end
end

if o.SearchShear                                          % slanted characters: straighten them by shearing
    bestScore = -1;  bestS = 0;
    for sh = -o.ShearRange:0.15:o.ShearRange
        Gh = shearFill(G, sh);
        rs = bestPolarity(Gh, o.Polarity, o.Strategies, o.HeightRange, o.LevelRegion, o.Levels, o.Select, o.Split, o.Open, o.Rules, o.Flat, o.Proj, o.Fix);
        sc = 0;
        if rs.n >= 3, sc = plateRowScore(rs.props.BoundingBox(rs.keep, :)) + 0.02 * rs.n; end
        if sc > bestScore + 1e-9 || (abs(sc - bestScore) <= 1e-9 && abs(sh) < abs(bestS)), bestScore = sc;  bestS = sh; end
    end
    if bestS ~= 0, G = shearFill(G, bestS); end
end

best = struct('n', -1);
for pass = 1:2                                            % pass 2 repeats after de-skewing
    [res, G] = binarise(G, o);
    best = res;
    if abs(res.angle) < 1.0 || pass == 2, break; end
    % rotate the plate so the character line becomes horizontal, then repeat
    [~, T] = geometricTransforms(G, 'rotate', -res.angle, 'bilinear');
    fillVal = median([G(1,:), G(end,:)]);
    G = warpImage(G, T, size(G), 'bilinear', 'reverse', fillVal);
end

chars = cell(1, best.n);
boxes = zeros(best.n, 4);
for k = 1:best.n
    lab = best.keep(k);
    bb = best.props.BoundingBox(lab, :);
    r = bb(2):bb(2)+bb(4)-1;  c = bb(1):bb(1)+bb(3)-1;
    mask = best.L(r, c) == lab;                           % this component only
    chars{k} = normalizeChar(mask, 32);
    boxes(k, :) = bb;
end
dbg.plate = G;  dbg.binary = best.BW;  dbg.labels = best.L;  dbg.angle = best.angle;
dbg.polarity = best.polarity;
end

function G = rotateFill(G, a)
% rotate by a degrees (counter-clockwise), filling the corners with the border colour
if a == 0, return; end
[~, T] = geometricTransforms(G, 'rotate', a, 'bilinear');
fillVal = median([G(1,:), G(end,:)]);
G = warpImage(G, T, size(G), 'bilinear', 'reverse', fillVal);
end

function G = shearFill(G, sh)
% horizontal shear about the plate centre (x' = x + sh * (y - yc)), border colour as filler
if sh == 0, return; end
[~, T] = geometricTransforms(G, 'shear', sh, 0, 'bilinear');
fillVal = median([G(1,:), G(end,:)]);
G = warpImage(G, T, size(G), 'bilinear', 'reverse', fillVal);
end

function G = channelImage(I, channel)
% grey image from a colour plate (a grey input is returned unchanged)
I = toDouble(I);
if size(I, 3) ~= 3, G = I;  return; end
switch lower(channel)
    case 'min',   G = min(I, [], 3);
    case 'max',   G = max(I, [], 3);
    case 'red',   G = I(:,:,1);
    case 'green', G = I(:,:,2);
    case 'blue',  G = I(:,:,3);
    otherwise,    G = toGray(I);
end
end

function [L, n] = projectionLabels(BW)
% Characters from projection profiles instead of connected components: the rows of the text line are found from the
% horizontal projection (rows that are almost full of ink are strips or frames and are skipped), the characters are the
% column runs of ink inside that band, and a run much wider than the line is cut at the valleys of its projection.
[H, W] = size(BW);
L = zeros(H, W);  n = 0;
rf = mean(BW, 2);
ok = rf >= 0.15 * max(rf(rf <= 0.92)) & rf <= 0.92;
if ~any(ok), return; end
d = diff([0; double(ok); 0]);  st = find(d == 1);  en = find(d == -1) - 1;
for k = numel(st):-1:2                                       % join runs separated by 2 rows or less
    if st(k) - en(k-1) <= 3, en(k-1) = en(k);  st(k) = [];  en(k) = []; end
end
[~, b] = max(arrayfun(@(i) sum(rf(st(i):en(i))), 1:numel(st)));
r0 = st(b);  r1 = en(b);  hb = r1 - r0 + 1;
if hb < 0.25 * H, return; end
band = BW(r0:r1, :);
cp = sum(band, 1);
ink = cp >= 0.12 * hb;
d = diff([0, double(ink), 0]);  cs = find(d == 1);  ce = find(d == -1) - 1;
for i = 1:numel(cs)
    c0 = cs(i);  c1 = ce(i);  w = c1 - c0 + 1;
    if w < 0.1 * hb, continue; end
    cuts = [];
    if w > 1.15 * hb, cuts = findCuts(cp(c0:c1), hb); end
    edges = [0, cuts, w];
    for j = 1:numel(edges) - 1
        a = c0 + edges(j);  e = c0 + edges(j+1) - 1;
        if e - a + 1 < 0.1 * hb, continue; end
        sub = band(:, a:e);
        if nnz(sub) < 0.04 * hb * hb, continue; end
        n = n + 1;
        blk = L(r0:r1, a:e);  blk(sub) = n;  L(r0:r1, a:e) = blk;
    end
end
end

function Gf = flattenRows(G, pol)
% subtract the background level of every row: for dark characters the 75th percentile of the row (the plate), for bright
% characters the 25th, so that a dark (or bright) strip across the whole plate gets the level of the plate, the characters stay
if strcmp(pol, 'dark'), q = 0.75; else, q = 0.25; end
S = sort(G, 2);
ref = S(:, max(1, round(q * size(G, 2))));
Gf = G - ref + mean(ref);
Gf = min(max(Gf, 0), 1);
end

function BW = removeLongRuns(BW)
% erase horizontal runs longer than 1.3 plate heights and vertical runs longer than 0.9 plate heights
[H, W] = size(BW);
for pass = 1:2
    if pass == 1, lim = 1.3 * H;  M = BW; else, lim = 0.9 * H;  M = BW.'; end
    for r = 1:size(M, 1)
        d = diff([0, double(M(r, :)), 0]);  st = find(d == 1);  en = find(d == -1) - 1;
        for k = find(en - st + 1 > lim)
            M(r, st(k):en(k)) = false;
        end
    end
    if pass == 1, BW = M; else, BW = M.'; end
end
end

function [res, G] = bestPolarity(G, polarity, strategies, hr, region, levels, select, split, open, rules, flat, proj, fix)
% Binarise with the requested strategies (global Otsu / local adaptive threshold) for
% dark and/or bright characters and keep the one with the best group of characters.
[H, W] = size(G);
if strcmpi(region, 'center')
    level = otsuThreshold(G(round(0.15*H):round(0.85*H), round(0.05*W):round(0.95*W)));
else
    level = otsuThreshold(G);
end
win = 2 * floor(0.45 * H / 2) + 1;                          % adaptive window ~ half the plate height
cands = {};
for pol = {'dark', 'bright'}
    if ~any(strcmpi(polarity, {'auto', pol{1}})), continue; end
    for how = strategies(:).'
        cands(end+1, :) = {pol{1}, how{1}};    %#ok<AGROW>
    end
end
res = struct('n', -1, 'score', 0, 'row', -1);
for k = 1:size(cands, 1)
    pol = cands{k,1};  how = cands{k,2};
    if strcmp(how, 'otsu'), lms = levels; else, lms = 1; end
    Gc = G;  lev = level;
    if flat                                                  % a shadow strip along the plate is removed row by row
        Gc = flattenRows(G, pol);
        if strcmpi(region, 'center'), lev = otsuThreshold(Gc(round(0.15*H):round(0.85*H), round(0.05*W):round(0.95*W))); else, lev = otsuThreshold(Gc); end
    end
    for lm = lms(:).'
        if strcmp(how, 'otsu')
            if strcmp(pol, 'dark'), BW = Gc < lm * lev; else, BW = Gc >= lm * lev; end
        else
            BW = adaptiveThreshold(Gc, win, 0.05, pol);
        end
        if open > 0, BW = morphOp(BW, 'open', makeSE('rect', [open, open])); end       % thin bridges (shadow strip, frame) go, strokes stay
        if rules, BW = removeLongRuns(BW); end
        r = groupCharacters(BW, hr, split, proj, fix);
        r.polarity = [pol ' (' how ')'];
        r.BW = BW;
        r.row = 0;
        if r.n >= 3, r.row = plateRowScore(r.props.BoundingBox(r.keep, :)); end
        if strcmp(select, 'row')
            better = r.row > res.row + 1e-9 || (abs(r.row - res.row) <= 1e-9 && r.n > res.n);
        else
            better = r.n > res.n || (r.n == res.n && r.score > res.score);
        end
        if better, res = r; end
    end
end
end

function r = groupCharacters(BW, hr, split, proj, fix)
% Find the largest set of same-height components that lie on one straight line.
[H, W] = size(BW);
if proj, [L, n] = projectionLabels(BW); else, [L, n] = labelComponents(BW, 8); end
if split, [L, n] = splitWideComponents(L, n); end
r = pickRow(L, n, H, W, hr);
for rep = 1:2                                               % two characters that touch: cut them and choose the row again (a second round for a piece that is still too wide)
    if ~fix || r.n < 3, break; end
    [L2, n2, did] = splitOutliers(L, n, r);
    if ~did, break; end
    r2 = pickRow(L2, n2, H, W, hr);
    if r2.n <= r.n, break; end
    r = r2;  L = L2;  n = n2;
end
end

function [L, n, did] = splitOutliers(L, n, r)
% A character of the row that is much wider than the others is two characters that touch (F + H, "20", "EE" of a blurred plate).
% It is cut at the lowest column of its vertical projection (near the middle of every part; 2 or 3 parts), but only where that column holds at most
% 22 % of the highest column: the merged F + H measured 0.11 to 0.13, the wide M and W of synthetic plates 0.27 to 0.40 (without this test the synthetic
% pipeline check fell from 93 % to 70 % characters). (Also cutting the components that
% were not kept because they are too wide for one character, "0943" of MH 20 EE 0943, gave "MH20EE0P43" and lost two held-out plates: not used.)
did = false;
bb = r.props.BoundingBox(r.keep, :);
w = bb(:, 3);  h = bb(:, 4);  k = numel(w);  hm = median(h);
for i = 1:k
    u = min(median(w([1:i-1, i+1:k])), 0.62 * hm);            % a single character: the others' width, but never wider than 0.62 x height
    if w(i) < 1.6 * u || w(i) < 0.65 * hm, continue; end
    [L, n, ok] = cutComponent(L, n, r.props.BoundingBox(r.keep(i), :), r.keep(i), min(3, max(2, round(w(i) / u))), hm);
    did = did || ok;
end
end

function [L, n, did] = cutComponent(L, n, bq, q, parts, hm)
% cut component q (bounding box bq) into 'parts' pieces at the lowest columns of its vertical projection near the equal divisions
did = false;
c = bq(1):bq(1) + bq(3) - 1;  rr = bq(2):bq(2) + bq(4) - 1;
w = bq(3);
mask = L(rr, c) == q;
pj = sum(mask, 1);
cuts = zeros(1, parts - 1);
for j = 1:parts - 1
    ex = j * w / parts;
    lo = max(2, round(ex - 0.3 * w / parts));  hi = min(w - 1, round(ex + 0.3 * w / parts));
    if lo > hi, return; end
    [~, im] = min(pj(lo:hi) + 1e-6 * abs((lo:hi) - ex));
    cuts(j) = lo + im - 1;
    if pj(cuts(j)) > 0.22 * max(pj), return; end             % no deep valley: one wide character (M, W), not two that touch
end
if any(diff([0, cuts, w]) < 0.2 * hm), return; end
piece = ones(1, numel(c));
for j = 1:numel(cuts), piece(cuts(j)+1:end) = j + 1; end
sub = L(rr, c);
for j = 2:parts
    n = n + 1;
    sub(mask & repmat(piece == j, numel(rr), 1)) = n;
end
L(rr, c) = sub;
did = true;
end

function r = pickRow(L, n, H, W, hr)
props = componentProps(L, n);
bb = props.BoundingBox;
touches = bb(:,1) <= 1 | bb(:,2) <= 1 | bb(:,1) + bb(:,3) > W | bb(:,2) + bb(:,4) > H;
ok = ~touches & bb(:,4) >= 0.25 * H & bb(:,4) <= 0.95 * H & ...
     props.Aspect <= 1.5 & props.Aspect >= 0.08 & props.Area >= 0.04 * H * H * 0.25;
idx = find(ok);
r = struct('n', 0, 'score', 0, 'keep', [], 'L', L, 'props', props, 'angle', 0);
if numel(idx) < 2, return; end

cx = props.Centroid(idx, 1);  cy = props.Centroid(idx, 2);  h = bb(idx, 4);
bestSet = [];  bestAngle = 0;
for a = 1:numel(idx)                                       % hypothesis: component a is typical
    sim = h >= hr(1) * h(a) & h <= hr(2) * h(a);               % wide window: Q has a tail, I is thin
    sim(a) = true;
    s = find(sim);
    if numel(s) < numel(bestSet), continue; end
    % robust line through the centroids: try every pair of the group as a model
    for i = 1:numel(s)
        for j = i+1:numel(s)
            dx = cx(s(j)) - cx(s(i));
            if abs(dx) < 1, continue; end
            slope = (cy(s(j)) - cy(s(i))) / dx;
            if abs(atan(slope)) > 25 * pi/180, continue; end
            pred = cy(s(i)) + slope * (cx(s) - cx(s(i)));
            inl = s(abs(cy(s) - pred) < 0.30 * h(a));
            if numel(inl) > numel(bestSet)
                bestSet = inl;  bestAngle = atan(slope) * 180/pi;
            end
        end
    end
    if numel(s) >= 2 && isempty(bestSet), bestSet = s(1); end
end
if numel(bestSet) < 2, return; end
[~, order] = sort(cx(bestSet));
keep = idx(bestSet(order));
r.n = numel(keep);
r.keep = keep;
r.score = sum(props.Area(keep));
r.angle = bestAngle;
end

function [L, n] = splitWideComponents(L, n)
% Cut components that are much wider than tall (touching characters) where their vertical projection is lowest.
% Only components of character height with width / height > 1.3 are cut (M and W reach about 1.2 and are kept).
% Cuts are made at the thin necks between characters (projection below 40 % of its maximum); a piece that is still
% much wider than a character is divided evenly (character pitch 0.72 x height) at the lowest column near every division.
H = size(L, 1);
props = componentProps(L, n);
bb = props.BoundingBox;
isCh = bb(:,4) >= 0.3 * H & bb(:,4) <= 0.95 * H;
wide = find(isCh & bb(:,3) > 1.3 * bb(:,4));
for q = wide(:).'
    c = bb(q, 1):bb(q, 1) + bb(q, 3) - 1;  r = bb(q, 2):bb(q, 2) + bb(q, 4) - 1;
    mask = L(r, c) == q;
    cuts = findCuts(sum(mask, 1), numel(r));
    if isempty(cuts), continue; end
    piece = ones(1, numel(c));
    for j = 1:numel(cuts), piece(cuts(j)+1:end) = j + 1; end      % piece 1 keeps the old label
    sub = L(r, c);
    for j = 2:numel(cuts) + 1
        n = n + 1;
        sub(mask & repmat(piece == j, numel(r), 1)) = n;
    end
    L(r, c) = sub;
end
end

function cuts = findCuts(proj, hq)
% columns after which a component is cut
w = numel(proj);
low = proj < 0.4 * max(proj);  low([1 2 end-1 end]) = false;
d = diff([0, double(low), 0]);  st = find(d == 1);  en = find(d == -1) - 1;
cuts = zeros(1, numel(st));
for k = 1:numel(st)
    seg = st(k):en(k);  [~, im] = min(proj(seg));  cuts(k) = seg(im);
end
cuts = pruneCuts(cuts, w, hq);
edges = [0, cuts, w];  extra = [];
for i = 1:numel(edges) - 1
    pw = edges(i+1) - edges(i);
    if pw > 1.3 * hq                                          % still a blob of several characters: divide evenly
        k = min(5, max(2, round(pw / (0.72 * hq))));
        for j = 1:k-1
            ex = edges(i) + j * pw / k;
            lo = max(edges(i) + 2, round(ex - 0.3 * pw / k));  hi = min(edges(i+1) - 1, round(ex + 0.3 * pw / k));
            if lo > hi, continue; end
            [~, im] = min(proj(lo:hi) + 1e-6 * abs((lo:hi) - ex));
            extra(end+1) = lo + im - 1; %#ok<AGROW>
        end
    end
end
cuts = pruneCuts(sort([cuts, extra]), w, hq);
end

function cuts = pruneCuts(cuts, w, hq)
% remove cuts that would leave a piece narrower than a quarter of the character height
while ~isempty(cuts)
    pw = diff([0, cuts, w]);
    [m, i] = min(pw);
    if m >= 0.25 * hq, break; end
    if i <= numel(cuts), cuts(i) = []; else, cuts(end) = []; end
end
end

function [res, G] = binarise(G, o)
% bestPolarity on the grey plate, or on its top-hat images (large bright / dark blobs removed)
if o.TopHat <= 0
    [res, G] = bestPolarity(G, o.Polarity, o.Strategies, o.HeightRange, o.LevelRegion, o.Levels, o.Select, o.Split, o.Open, o.Rules, o.Flat, o.Proj, o.Fix);
    return
end
SE = makeSE('disk', max(3, round(o.TopHat * size(G, 1))));
res = struct('n', -1, 'score', 0, 'row', -1);
if any(strcmpi(o.Polarity, {'auto', 'bright'}))
    T = morphOp(G, 'tophat', SE);  T = T / max(max(T(:)), eps);               % bright characters on a flat background
    r = bestPolarity(T, 'bright', o.Strategies, o.HeightRange, o.LevelRegion, o.Levels, o.Select, o.Split, o.Open, o.Rules, o.Flat, o.Proj, o.Fix);
    r.polarity = [r.polarity ', top-hat'];
    if r.n > res.n || (r.n == res.n && r.score > res.score), res = r; end
end
if any(strcmpi(o.Polarity, {'auto', 'dark'}))
    T = morphOp(G, 'blackhat', SE);  T = 1 - T / max(max(T(:)), eps);         % dark characters (low values)
    r = bestPolarity(T, 'dark', o.Strategies, o.HeightRange, o.LevelRegion, o.Levels, o.Select, o.Split, o.Open, o.Rules, o.Flat, o.Proj, o.Fix);
    r.polarity = [r.polarity ', top-hat'];
    if r.n > res.n || (r.n == res.n && r.score > res.score), res = r; end
end
end
