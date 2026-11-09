function [X, patches] = makeHardNegatives(tpl, n)
%MAKEHARDNEGATIVES  Synthetic look-alikes of licence plates that are NOT plates.
%   X = MAKEHARDNEGATIVES(tpl, n) returns n rows of PLATEFEATURES for rendered
%   non-plates that the plate SVM must learn to reject. Nine kinds, in equal parts:
%     1  overlay text   date/time stamps and counters: light digits and separators
%                       (/ : - space) on a dark background, no frame
%     2  block signs    road signs / shop signs with dense square (CJK-like) glyphs
%                       on a blue, green, white or red board
%     3  latin signs    long white lines of text (10-22 characters) on blue/green boards
%     4  clutter        night scenes with bright lights, sky and foliage, road with
%                       lane marks
%     5  route labels   a small black rounded frame with 1-3 white characters (8C, 6, N1)
%                       next to white arrows and orange/red shields on a blue or green
%                       direction-sign board (overhead motorway signs)
%     6  head-light pairs   two bright glows side by side in the dark
%     7  tail-light bars    a glowing red horizontal light strip (and end lamps) on a dark car
%     8  lit shop signs     bright warm-white / red boards with short glowing Latin words
%     9  wet-road reflections  vertical red / white light smears on dark asphalt
%   Everything is generated from the glyph templates and random shapes, not from any
%   photograph. Use RNG before calling for reproducible data. [X, patches] also returns
%   the rendered images (cell array) for inspection.

X = [];  patches = cell(1, n);
for k = 1:n
    switch mod(k - 1, 9) + 1
        case 1, P = overlayPatch(tpl);
        case 2, P = blockSignPatch();
        case 3, P = latinSignPatch(tpl);
        case 4, P = clutterPatch();
        case 5, P = routeLabelPatch(tpl);
        case 6, P = headlightPairPatch();
        case 7, P = tailLightBarPatch();
        case 8, P = litShopSignPatch(tpl);
        otherwise, P = wetRoadPatch();
    end
    sg = 0.2 + 1.3 * rand;                                   % camera blur and noise
    P = spatialFilter(P, gaussianKernel(2*ceil(3*sg) + 1, sg));
    P = min(max(P + 0.03 * rand * randn(size(P)), 0), 1);
    patches{k} = P;
    f = plateFeatures(P);
    if isempty(X), X = zeros(n, numel(f)); end
    X(k, :) = f;
end
end

% ---------------------------------------------------------------------------------
function P = overlayPatch(tpl)
% light digits and separators on a dark background (date / time stamps)
v = randi(size(tpl.variants, 1));
H = 22 + randi(40);                                          % character height in pixels
patterns = {'DDDD/DD/DD DD:DD:DD', 'DD-DD-DDDD DD:DD', 'DDDD-DD-DD', 'DD:DD:DD', 'DDDD DDDD', 'DD/DD/DD  DD:DD', 'DDDDDD'};
pat = patterns{randi(numel(patterns))};
cells = {};
for q = 1:numel(pat)
    switch pat(q)
        case 'D', cells{end+1} = glyphImg(tpl, v, '0' + randi([0 9]) - 0, H); %#ok<AGROW>
        case '/', cells{end+1} = sepImg('/', H); %#ok<AGROW>
        case ':', cells{end+1} = sepImg(':', H); %#ok<AGROW>
        case '-', cells{end+1} = sepImg('-', H); %#ok<AGROW>
        otherwise, cells{end+1} = zeros(round(1.2 * H), round(0.5 * H)); %#ok<AGROW>
    end
end
T = joinCells(cells, round(1.2 * H), round(0.12 * H));
mx = round(0.4 * H + rand * 0.5 * H);  my = round(0.25 * H + rand * 0.3 * H);
[h, w] = size(T);
bg = rand * 0.25;
B = bg + 0.08 * rand * smoothNoise(h + 2*my, w + 2*mx, 6);
txt = 0.8 + 0.2 * rand;
ink = zeros(h + 2*my, w + 2*mx);  ink(my+1:my+h, mx+1:mx+w) = T;
col = [txt, txt, txt];
if rand < 0.3, col = [txt, txt, 0.3 * txt]; end             % yellow overlay
P = zeros([size(ink), 3]);
for ch = 1:3, P(:,:,ch) = B .* (1 - ink) + col(ch) * ink; end
end

function P = blockSignPatch()
% rows of dense square glyphs (like CJK text) on a coloured board
boards = [0.10 0.30 0.70; 0.10 0.50 0.30; 0.92 0.92 0.92; 0.75 0.15 0.15; 0.95 0.80 0.15];
bgc = boards(randi(size(boards, 1)), :);
fg = [1 1 1];  if sum(bgc) > 2 || rand < 0.15, fg = [0.05 0.05 0.05]; end
C = 26 + randi(34);                                          % glyph size
nc = 4 + randi(6);
cells = cell(1, nc);
for q = 1:nc, cells{q} = strokeGlyph(C); end
T = joinCells(cells, C, round(0.12 * C));
mx = round(0.5 * C + rand * 0.5 * C);  my = round(0.3 * C + rand * 0.3 * C);
[h, w] = size(T);
ink = zeros(h + 2*my, w + 2*mx);  ink(my+1:my+h, mx+1:mx+w) = T;
P = zeros([size(ink), 3]);
for ch = 1:3, P(:,:,ch) = bgc(ch) * (1 - ink) + fg(ch) * ink; end
end

function P = latinSignPatch(tpl)
% a long line of capital letters (road / shop / direction signs)
v = randi(size(tpl.variants, 1));
H = 18 + randi(26);
n = 10 + randi(13);
letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
cells = cell(1, n);
for q = 1:n
    if rand < 0.15, cells{q} = zeros(round(1.2 * H), round(0.5 * H));
    else, cells{q} = glyphImg(tpl, v, letters(randi(26)), H); end
end
T = joinCells(cells, round(1.2 * H), round(0.15 * H));
boards = [0.10 0.30 0.70; 0.10 0.50 0.30; 0.15 0.15 0.20];
bgc = boards(randi(size(boards, 1)), :);
mx = round(0.8 * H);  my = round(0.5 * H);
[h, w] = size(T);
ink = zeros(h + 2*my, w + 2*mx);  ink(my+1:my+h, mx+1:mx+w) = T;
P = zeros([size(ink), 3]);
for ch = 1:3, P(:,:,ch) = bgc(ch) * (1 - ink) + 0.95 * ink; end
end

function P = routeLabelPatch(tpl)
% small black rounded frame with 1-3 white characters (route number such as 8C, 6, N1) next to
% white arrows and orange / red shields on a blue or green direction-sign board
v = randi(size(tpl.variants, 1));
H = 16 + randi(26);                                          % character height in pixels
nch = randi(3);
pool = ['0':'9', 'A':'Z'];
cells = cell(1, nch);
for q = 1:nch, cells{q} = glyphImg(tpl, v, pool(randi(numel(pool))), H); end
T = joinCells(cells, round(1.2 * H), round(0.15 * H));
[th, tw] = size(T);
fm = round(0.3 * H);
fh = th + 2 * fm;  fw = tw + 2 * fm;                         % size of the label frame
boards = [0.10 0.30 0.70; 0.10 0.50 0.30];
bgc = boards(randi(2), :);
order = [0, randi(2, 1, randi(3))];                          % 0 = label frame, 1 = arrow, 2 = shield
if rand < 0.4, order = order(randperm(numel(order))); end
gap = round(0.35 * fh);  sz = round(0.85 * fh);
Hb = round(fh * (1.3 + 0.5 * rand));
W = gap;
for q = order
    if q == 0, W = W + fw + gap; else, W = W + sz + gap; end
end
P = repmat(reshape(bgc, 1, 1, 3), [Hb W 1]);
x = gap;
for q = order
    if q == 0
        r0 = round((Hb - fh) / 2) + 1;
        P = pasteMask(P, roundedMask(fh, fw), [0.04 0.04 0.04], r0, x + 1);
        ink = zeros(fh, fw);  ink(fm+1:fm+th, fm+1:fm+tw) = T;
        P = pasteMask(P, ink, [1 1 1], r0, x + 1);
        x = x + fw + gap;
    else
        r0 = round((Hb - sz) / 2) + 1;
        if q == 1
            P = pasteMask(P, arrowMask(sz, randi(4)), [1 1 1], r0, x + 1);
        else
            col = [1 0.55 0.1];  if rand < 0.4, col = [0.85 0.1 0.1]; end
            P = pasteMask(P, roundedMask(sz, sz), col, r0, x + 1);
            a = max(2, round(0.3 * sz));
            inner = zeros(sz);  inner(a:sz-a, a:sz-a) = 1;
            P = pasteMask(P, inner, 0.5 * col, r0, x + 1);
        end
        x = x + sz + gap;
    end
end
P = min(max(P, 0), 1);
end

function M = roundedMask(h, w)
% filled rectangle with rounded corners
[x, y] = meshgrid(1:w, 1:h);
rr = 0.25 * min(h, w);
dx = max(abs(x - (w + 1) / 2) - (w / 2 - rr), 0);
dy = max(abs(y - (h + 1) / 2) - (h / 2 - rr), 0);
M = double(hypot(dx, dy) <= rr);
end

function M = arrowMask(sz, dir)
% block arrow (stem + triangular head); dir 1..4 turns it by 90 degrees
[x, y] = meshgrid(linspace(0, 1, sz), linspace(0, 1, sz));
stem = abs(x - 0.5) <= 0.12 & y >= 0.08 & y <= 0.55;
head = y > 0.5 & y <= 0.92 & abs(x - 0.5) <= 0.4 * (0.92 - y) / 0.42;
M = rot90(double(stem | head), dir - 1);
end

function P = pasteMask(P, M, col, r0, c0)
% blend colour col into P where the mask M is 1, with the top-left corner at (r0, c0)
[h, w] = size(M);
r = r0:r0 + h - 1;  c = c0:c0 + w - 1;
okR = r >= 1 & r <= size(P, 1);  okC = c >= 1 & c <= size(P, 2);
r = r(okR);  c = c(okC);  M = M(okR, okC);
for ch = 1:3, P(r, c, ch) = P(r, c, ch) .* (1 - M) + col(ch) * M; end
end

function P = headlightPairPatch()
% two bright head-lights (white / yellowish glows with halos) on a dark front
h = 28 + randi(60);  w = round(h * (2.5 + 4 * rand));
B = 0.02 + 0.08 * rand * smoothNoise(h, w, 5);
P = repmat(B, [1 1 3]);
[x, y] = meshgrid(1:w, 1:h);
cy = h * (0.35 + 0.3 * rand);  gapx = w * (0.35 + 0.35 * rand);  r = (0.18 + 0.2 * rand) * h;
col = [1 1 0.92];  if rand < 0.4, col = [1 0.85 0.5]; end
for q = [-1 1]
    cx = w / 2 + q * gapx / 2;
    m = exp(-(((x - cx) / (1.5 * r)).^2 + ((y - cy) / r).^2) * 1.1);
    core = double(hypot(x - cx, y - cy) < 0.45 * r);
    for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + col(ch) * (0.8 * m + core)); end
end
P = min(max(P, 0), 1);
end

function P = tailLightBarPatch()
% glowing red light strip across the back of a dark car, optionally with lamps at both ends
h = 28 + randi(60);  w = round(h * (2.5 + 4 * rand));
B = 0.03 + 0.08 * rand * smoothNoise(h, w, 5);
P = repmat(B, [1 1 3]);
[x, y] = meshgrid(1:w, 1:h);
cy = h * (0.3 + 0.4 * rand);  t = 0.04 + 0.08 * rand;
bar = exp(-(((y - cy) / (t * h + 1)).^2) * 1.5) .* double(x > 0.1 * w & x < 0.9 * w);
col = [1, 0.1 + 0.2 * rand, 0.05];
for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + col(ch) * bar); end
if rand < 0.7
    for cx = [0.08 * w, 0.92 * w]
        m = exp(-(((x - cx) / (0.07 * w + 2)).^2 + ((y - cy) / (0.25 * h + 2)).^2));
        for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + col(ch) * m); end
    end
end
P = min(max(P, 0), 1);
end

function P = litShopSignPatch(tpl)
% bright board (warm white, yellow or red) with a short glowing Latin word, glow around it
v = randi(size(tpl.variants, 1));
H = 18 + randi(26);
n = 4 + randi(8);
letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
cells = cell(1, n);
for q = 1:n, cells{q} = glyphImg(tpl, v, letters(randi(26)), H); end
T = joinCells(cells, round(1.2 * H), round(0.18 * H));
boards = [0.98 0.92 0.70; 0.95 0.80 0.25; 0.85 0.12 0.12; 0.95 0.95 0.95];
bgc = boards(randi(size(boards, 1)), :);
fg = [0.1 0.05 0.05];  if sum(bgc) < 2, fg = [1 1 1]; end
mx = round(0.7 * H);  my = round(0.5 * H);
[h, w] = size(T);
ink = zeros(h + 2 * my, w + 2 * mx);  ink(my+1:my+h, mx+1:mx+w) = T;
P = zeros([size(ink), 3]);
for ch = 1:3, P(:,:,ch) = bgc(ch) * (1 - ink) + fg(ch) * ink; end
P = darkBorder(P, round(0.5 * H));                          % dark surroundings with a glow
g = gaussianKernel(2 * ceil(2.5 * 0.4 * H) + 1, 0.4 * H);
Gl = spatialFilter(P, g);
P = min(1, 0.55 * P + 0.9 * Gl);
end

function P = wetRoadPatch()
% dark wet asphalt with elongated vertical reflections of red / white lights
h = 28 + randi(60);  w = round(h * (2.5 + 4 * rand));
B = 0.04 + 0.06 * rand * smoothNoise(h, w, 6);
P = repmat(B, [1 1 3]);
[x, y] = meshgrid(1:w, 1:h);
for q = 1:randi(5) + 1
    cx = rand * w;  sx = (0.01 + 0.03 * rand) * w + 1;  top = rand * 0.4 * h;
    m = exp(-((x - cx) / sx).^2) .* double(y >= top) .* exp(-(y - top) / (0.5 * h));
    col = [1, 0.1 + 0.2 * rand, 0.05];  if rand < 0.4, col = [1 1 0.9]; end
    for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + col(ch) * 0.9 * m); end
end
P = min(max(P, 0), 1);
end

function Q = darkBorder(P, r)
% surround an RGB image with a dark border of r pixels (base MATLAB)
[h, w, c] = size(P);
Q = 0.03 * ones(h + 2 * r, w + 2 * r, c);
Q(r+1:r+h, r+1:r+w, :) = P;
end

function P = clutterPatch()
% night lights, sky/foliage, road with lane marks
h = 28 + randi(60);  w = round(h * (2.5 + 4 * rand));
mode = randi(4);
switch mode
    case 1                                                    % bright lights in the dark
        B = 0.03 + 0.06 * rand * smoothNoise(h, w, 4);
        P = repmat(B, [1 1 3]);
        for q = 1:randi(5)
            cx = rand * w;  cy = rand * h;  r = 2 + rand * 0.25 * h;
            [x, y] = meshgrid(1:w, 1:h);
            m = exp(-(((x - cx) / (1.6 * r)).^2 + ((y - cy) / r).^2) * 1.2);
            c = [1, 0.3 + 0.6 * rand, 0.2 * rand];  if rand < 0.4, c = [1 1 0.9]; end
            for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + c(ch) * m); end
        end
    case 2                                                    % sky and foliage
        sky = linspace(0.75, 0.55, h).' * ones(1, w);
        F = smoothNoise(h, w, 3);
        trees = double(F > 0.15 + 0.3 * rand);
        P = cat(3, sky .* (1 - trees) + 0.15 * trees, sky .* (1 - trees) + 0.25 * trees, (sky + 0.1) .* (1 - trees) + 0.1 * trees);
    case 3                                                    % road with lane marks
        g = 0.3 + 0.25 * rand;
        B = g + 0.06 * smoothNoise(h, w, 8);
        P = repmat(B, [1 1 3]);
        a = (rand - 0.5) * 1.2;
        [x, y] = meshgrid(1:w, 1:h);
        for q = 1:randi(3)
            d = abs((y - h * rand) - a * (x - w * rand));
            m = double(d < 1 + 0.06 * h);
            for ch = 1:3, P(:,:,ch) = max(P(:,:,ch), 0.9 * m); end
        end
    otherwise                                                 % bumper / car-body shadows
        B = 0.1 + 0.5 * smoothNoise(h, w, 5);
        P = repmat(min(max(B, 0), 1), [1 1 3]);
        P(round(0.3*h):round(0.7*h), round(0.2*w):round(0.8*w), :) = 0.05 + 0.1 * rand;
end
P = min(max(P, 0), 1);
end

% ---- helpers ---------------------------------------------------------------------
function g = glyphImg(tpl, v, ch, H)
idx = find(tpl.chars == char(ch), 1);
if isempty(idx), idx = 1; end
g = double(tpl.glyphs{v}{idx}) / 255;
g = imResize(g, max(2, round(size(g) * (H / tpl.capH(v)))), 'bilinear');
end

function S = sepImg(kind, H)
h = round(1.2 * H);  w = max(4, round(0.45 * H));
S = zeros(h, w);
t = max(1, round(0.1 * H));
switch kind
    case '/'
        for r = 1:h, c = round(w - 1 - (r - 1) / (h - 1) * (w - 3)); S(r, max(1, c - t + 1):min(w, c + t)) = 1; end
    case ':'
        c = round(w / 2);  S(round(0.3*h) + (0:t), c - floor(t/2):c + floor(t/2) + 1) = 1;  S(round(0.7*h) + (0:t), c - floor(t/2):c + floor(t/2) + 1) = 1;
    case '-'
        S(round(h / 2) + (0:t), 2:w-1) = 1;
end
S = S(1:h, 1:w);
end

function T = joinCells(cells, H, gap)
% put glyph images side by side, vertically centred in a strip of height H
T = zeros(H, 0);
for q = 1:numel(cells)
    g = cells{q};
    [gh, gw] = size(g);
    col = zeros(H, gw);
    r0 = max(1, round((H - gh) / 2) + 1);
    r1 = min(H, r0 + gh - 1);
    col(r0:r1, :) = g(1:(r1 - r0 + 1), :);
    T = [T, col, zeros(H, gap)]; %#ok<AGROW>
end
end

function G = strokeGlyph(C)
% a dense square glyph made of random strokes (stands for a CJK character)
G = zeros(C);
[x, y] = meshgrid(linspace(0, 1, C), linspace(0, 1, C));
nS = 5 + randi(5);
for s = 1:nS
    p = 0.08 + 0.84 * rand(2, 2);
    if rand < 0.5, p(2,2) = p(1,2); elseif rand < 0.5, p(2,1) = p(1,1); end   % many strokes are straight
    d = distToSegment(x, y, p(1,:), p(2,:));
    G = max(G, double(d < 0.07));
end
end

function d = distToSegment(x, y, a, b)
v = b - a;  L2 = max(sum(v.^2), 1e-9);
t = min(max(((x - a(1)) * v(1) + (y - a(2)) * v(2)) / L2, 0), 1);
d = hypot(x - (a(1) + t * v(1)), y - (a(2) + t * v(2)));
end

function N = smoothNoise(h, w, s)
% smooth random field in [0,1]: low-resolution noise enlarged with bilinear interpolation
N = rand(max(2, ceil(h / s)), max(2, ceil(w / s)));
N = imResize(N, [h w], 'bilinear');
N = (N - min(N(:))) / max(max(N(:)) - min(N(:)), eps);
end
