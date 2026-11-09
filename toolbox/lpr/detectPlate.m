function [bbox, plateImg, dbg] = detectPlate(img, varargin)
%DETECTPLATE  Locate the license plate in a photo using Modules 1-3 (no learning).
%   [bbox, plateImg, dbg] = DETECTPLATE(img, 'Name', value, ...)
%   bbox     : [x y w h] in the coordinates of the input image ([] if none found)
%   plateImg : RGB crop of the plate
%   dbg      : intermediate images of the chosen scale, the list of all candidates, dbg.rejected
%              (true: no region was accepted), dbg.reason ('svm': the best region scored below
%              MinPlateScore, 'characters': no region had MinChars separable characters) and
%              dbg.guess (the best region by SVM score when reason is 'svm')
%   Options  : 'Widths'  working widths in pixels (default [640 960 1440]); widths
%                        larger than the image are dropped, so a 640 px photo is
%                        analysed at 640 px only
%              'Aspect'  [min max] accepted blob width/height (default [2 13]); the
%                        blob covers only the text row, so it is wider than the plate
%              'CloseWidth' width of the horizontal closing as a fraction of 640 px
%                        (default 0.07, i.e. 45 px at every scale); must exceed the gap
%                        between character groups such as "ABC" and "1234"
%              'Methods' candidate generators: 'edges' (vertical-edge blobs), 'chains' (rows of
%                        character-sized blobs) and 'windows' (sliding window scored by the plate
%                        SVM, see SLIDINGPLATECANDIDATES; only with 'PlateModel'); default all
%              'WindowTop' number of sliding windows added to the candidates (default 12) and 'WindowWidths' the plate widths the windows look for (pixels of the 960 px working copy, default [90 122 165 225 305 415] of SLIDINGPLATECANDIDATES;
%                        smaller values find far plates but cost time) and 'WindowMin' the lowest plate-SVM score a window needs
%                        (default -0.6; -0.95 found no extra plate on the test photos but doubled the time and added false regions)
%              'Original' the photo before its exposure was repaired (NORMALIZEEXPOSURE): the sliding
%                        windows are then also searched in it, because the gamma boost of a dark photo
%                        amplifies noise and can hide a small plate (same size as the input)
%              'Extra'   cell array of further versions of the photo (same size, e.g. a locally equalised copy of a dark photo):
%                        the sliding windows are searched in them too and a candidate keeps its best plate-SVM score
%                        over all versions
%              'Split'   true (default): the character check may cut touching characters apart (see SEGMENTPLATEBEST)
%              'ChainWidths' working widths of the character-row search (default [960 1440]; RECOGNIZEPLATES adds 2000, which lets the blurred
%                        characters of a big night photo come apart) and 'ChainOffsets' (default 0.05; RECOGNIZEPLATES adds 0.15, which thick strokes need)
%                        - on the 16 held-out photos the wider search gained one plate and lost another, so single-plate reading keeps the defaults
%              'PlateModel' plate / not-plate SVM from TRAINPLATEMODEL. When given, every
%                        candidate is scored by the SVM (PLATESCORE) and the SVM score
%                        decides together with the character-row check
%              'Verify'  true (default): the best candidates are checked by trying to
%                        segment characters in them and the region that contains the
%                        most regular row of characters wins
%              'TopK'    number of candidates kept after merging (default 10)
%              'MinPlateScore' with a plate SVM: if even the best candidate has a lower
%                        SVM decision value, nothing is returned (default -0.5; on the
%                        real photos every readable plate scored >= -0.29, while half of
%                        the wrongly chosen regions scored below -0.5)
%              'VerifyTop' with a plate SVM: number of its best candidates that also get
%                        the character-row check (default 5; if none of them passes, the next
%                        groups of the same size are checked, three groups at most)
%              'MinChars' with 'Verify': a candidate in which fewer than this many characters
%                        can be cut out (3 characters = a route label or sign, not a plate) gets
%                        -Inf and the next best region can win; if no region is left, nothing
%                        is returned and dbg.reason is 'characters' (default 4)
%              'RefineRounds' how many times the shift / shift / resize search is repeated (default 1; more rounds also try resizing by
%                        0.8 and 1.25. Tried 4 rounds for RECOGNIZEPLATES: the third plate of the night photo was still not reached, the time went from
%                        60 to 100 s, so it is not used)
%              'RefineTop' number of the best sliding windows whose position and size are fitted to the
%                        plate by a small local search on the plate-SVM score, kept only if the window keeps
%                        all its characters (a window that cuts off a letter reads wrongly: DR 3898 -> JR 3898);
%                        0 = off (default 3). Trade-off measured on the held-out photos: it repairs the
%                        window of car_07 but the SVM also likes a tighter window that drops the first letter
%                        of car_06 (one plate lost), so the net effect there is zero
%              'SatPenalty' soft penalty (SVM units, default 1; 0 = off) for a region of which more than 35 %
%                        of the pixels are saturated (luminance > 0.97): a lamp, head-light glare or a
%                        burnt-out plate cannot be read
%              'SizeWeight' with a plate SVM: adds SizeWeight * clamp(log2(boxWidth / 100), -1, 1) to the
%                        score of every candidate (prefers larger plates; default 0 = off)
%              'CenterWeight' adds CenterWeight * closeness of the box centre to the photo centre
%                        (1 at the centre, 0 at the corners; default 0 = off)
%              'CharModel' binary character-validity SVM (TRAINCHARVALIDMODEL, model.charValid): the components
%                        cut out of a candidate must look like characters (CHARSLOOKVALID); streaks and blobs do not
%                        count, so a wall, a van body or a grille cannot pass as a plate with 4 "characters"
%              'TopZone' soft penalty of 1 SVM unit for a region whose centre lies in the top
%                        part of the photo (default 0.15 = top 15 %; overhead signs, camera
%                        overlays); 0 = off
%
%   Pipeline (repeated for every working width)
%     1. resize (Module 3, bilinear interpolation)
%     2. contrast stretch + Gaussian smoothing (Module 1)
%     3. vertical Sobel edges, Otsu threshold (Module 2) - characters create a
%        dense band of vertical strokes
%     4. morphological closing joins the strokes into one blob, opening removes
%        thin clutter, holes are filled (Module 2)
%     5. connected components are kept when their shape (aspect ratio, extent)
%        looks like a plate and are ranked by edge density, black/white contrast
%        and plate-like colour.
%   Candidates of all scales are merged (non-maximum suppression). With 'Verify' the
%   top candidates are cropped from the original photo, run through SEGMENTCHARS, and
%   scored by how plate-like the character row is (3-12 characters of similar height
%   on a line, evenly spaced, filling a sensible part of the crop).

p = inputParser;
p.addParameter('Width', []);                       % legacy: one fixed working width
p.addParameter('Widths', [640 960 1440]);
p.addParameter('Aspect', [2 13]);
p.addParameter('CloseWidth', 0.07);
p.addParameter('Methods', {'edges', 'chains', 'windows'});
p.addParameter('WindowTop', 12);
p.addParameter('WindowMin', -0.6);
p.addParameter('WindowWidths', []);
p.addParameter('Original', []);
p.addParameter('Extra', {});
p.addParameter('Split', true);
p.addParameter('ChainWidths', [960 1440]);
p.addParameter('ChainOffsets', 0.05);
p.addParameter('PlateModel', []);
p.addParameter('Verify', true);
p.addParameter('TopK', 10);
p.addParameter('VerifyTop', 5);
p.addParameter('MinPlateScore', -0.5);
p.addParameter('MinChars', 4);
p.addParameter('CharModel', []);
p.addParameter('TopZone', 0.15);
p.addParameter('SatPenalty', 1);
p.addParameter('RefineTop', 3);
p.addParameter('RefineRounds', 1);
p.addParameter('SizeWeight', 0);
p.addParameter('CenterWeight', 0);
p.parse(varargin{:});
o = p.Results;

img = toDouble(img);
[H0, W0, ~] = size(img);
widths = o.Widths;
if ~isempty(o.Width), widths = o.Width; end
small = widths <= 2.5 * W0;                                % small photos are enlarged (at most 2.5x): tiny plates need it
if ~any(small), small(1) = true; widths(1) = round(2.5 * W0); end
widths = unique(widths(small));
closePx = max(9, round(o.CloseWidth * 640));

% ---- candidates at every scale ---------------------------------------------------
cand = struct('box', {}, 'score', {}, 'scale', {}, 'verify', {});
alts = {};                                                 % other versions of the photo that are searched too (same size)
if ~isempty(o.Original) && size(o.Original, 1) == H0 && size(o.Original, 2) == W0, alts{end+1} = toDouble(o.Original); end
for a = 1:numel(o.Extra)
    if size(o.Extra{a}, 1) == H0 && size(o.Extra{a}, 2) == W0, alts{end+1} = toDouble(o.Extra{a}); end %#ok<AGROW>
end
scaleDbg = cell(1, numel(widths));
for q = 1:numel(widths)
    [c, scaleDbg{q}] = scaleCandidates(img, widths(q), closePx, o.Aspect);
    if any(strcmp(o.Methods, 'edges')), cand = [cand, c]; end %#ok<AGROW>
end
if any(strcmp(o.Methods, 'chains'))
    for Wt = unique(min(o.ChainWidths, round(2.5 * W0)))
        cand = [cand, chainCandidates(img, Wt, o.ChainOffsets)]; %#ok<AGROW>
    end
end

% ---- sliding windows scored by the plate SVM (second candidate source, needs the SVM) ----------------
winCand = struct('box', {}, 'score', {}, 'scale', {}, 'verify', {});
winOpt = {};  if ~isempty(o.WindowWidths), winOpt = {'Widths', o.WindowWidths}; end
if any(strcmp(o.Methods, 'windows')) && ~isempty(o.PlateModel)
    wc = slidingPlateCandidates(img, o.PlateModel, 'MinScore', o.WindowMin, 'MaxOut', o.WindowTop, winOpt{:});
    for a = 1:numel(alts)                                   % the photo before the exposure repair, equalised copies, ...
        wc = [wc, slidingPlateCandidates(alts{a}, o.PlateModel, 'MinScore', o.WindowMin, 'MaxOut', o.WindowTop, winOpt{:})]; %#ok<AGROW>
    end
    for i = 1:numel(wc)
        winCand(end+1) = struct('box', wc(i).box, 'score', 0.5, 'scale', widths(end) / W0, 'verify', NaN); %#ok<AGROW>
    end
end

bbox = [];  plateImg = [];
if isempty(cand), cand = struct('box', {}, 'score', {}, 'scale', {}, 'verify', {}); end
dbg = struct('scale', 1, 'edges', [], 'blobs', [], 'candidates', zeros(0, 4), 'scores', [], 'working', [], 'all', cand, 'chosen', 0, 'rejected', false, 'reason', '', 'guess', []);
if isempty(cand) && isempty(winCand)
    dbg = fillDbg(dbg, scaleDbg{end});
    return
end

% ---- merge scales: non-maximum suppression on overlapping boxes -----------------------
[~, order] = sort([cand.score], 'descend');
cand = cand(order);
keep = true(1, numel(cand));
for i = 1:numel(cand)
    if ~keep(i), continue; end
    for j = i+1:numel(cand)
        if keep(j) && boxIou(cand(i).box, cand(j).box) > 0.4, keep(j) = false; end
    end
end
cand = cand(keep);
cand = cand(1:min(numel(cand), o.TopK));

% sliding windows: plates the blob detectors miss (appended after the merge above)
nBlob = numel(cand);
for i = 1:numel(winCand)
    dup = false;
    for j = 1:numel(cand)
        if boxIou(winCand(i).box, cand(j).box) > 0.6, dup = true; break, end
    end
    if ~dup, cand(end+1) = winCand(i); end %#ok<AGROW>
end

% ---- rank the candidates: plate SVM and/or character-row check ----------------------------------
best = 1;
useOrig = ~isempty(alts);
imgs = [{img}, alts];                                      % the characters are cut out of the first version that gives enough of them
for i = 1:numel(cand), cand(i).svm = NaN;  cand(i).nChars = NaN;  cand(i).src = 1; end
if ~isempty(o.PlateModel)
    for i = 1:numel(cand)
        crop = cropBox(img, cand(i).box);
        if size(crop, 1) >= 8 && size(crop, 2) >= 16
            sv = plateScore(o.PlateModel, crop);
            for a = 1:numel(alts), sv = max(sv, plateScore(o.PlateModel, cropBox(alts{a}, cand(i).box))); end   % best of repaired / original / equalised photo
            cand(i).svm = sv - regionPenalty(crop, cand(i).box, size(img), o.TopZone, o.SatPenalty);
        else
            cand(i).svm = -5;
        end
    end
end
if ~isempty(o.PlateModel) && o.RefineTop > 0 && numel(cand) > nBlob      % fit the best windows to the plate
    wi = nBlob + 1:numel(cand);
    [~, oo] = sort([cand(wi).svm], 'descend');
    for i = wi(oo(1:min(o.RefineTop, numel(oo))))
        c1 = refineWindow(cand(i), img, o.PlateModel, o.TopZone, o.SatPenalty, alts, o.RefineRounds);
        if isequal(c1.box, cand(i).box), continue; end
        if o.Verify
            % the SVM score alone can prefer a window that cuts a character off (a held-out plate lost its
            % first letter that way): keep the refined window only if it keeps all the characters and
            % scores at least as well with the character-row check
            c0 = checkCandidate(cand(i), imgs, o.MinChars, o.CharModel, false);
            c1 = checkCandidate(c1, imgs, o.MinChars, o.CharModel, false);
            if c1.nChars >= c0.nChars && c1.svm + 0.5 * c1.verify >= c0.svm + 0.5 * c0.verify
                cand(i) = c1;
            else
                cand(i) = c0;
            end
        else
            cand(i) = c1;
        end
    end
end
splitNow = false;                                          % touching characters are cut apart only if no region has enough characters
while numel(cand) >= 1 && (o.Verify || ~isempty(o.PlateModel))
    top = max([cand.score]);
    total = zeros(1, numel(cand));
    useSvm = ~isempty(o.PlateModel);
    for i = 1:numel(cand), if isnan(cand(i).nChars), cand(i).verify = 0; end, end   % windows checked above keep their result
    if useSvm
        [~, ordS] = sort([cand.svm], 'descend');                         % character-row check for the SVM's favourites first
    else
        ordS = 1:numel(cand);
    end
    if o.Verify
        nChunk = numel(cand);
        if useSvm, nChunk = o.VerifyTop; end
        done = 0;
        while done < numel(ordS)
            for i = ordS(done + 1:min(done + nChunk, numel(ordS)))
                if isnan(cand(i).nChars), cand(i) = checkCandidate(cand(i), imgs, o.MinChars, o.CharModel, splitNow); end
            end
            done = min(done + nChunk, numel(ordS));
            if any([cand.nChars] >= o.MinChars) || done >= 3 * nChunk, break; end   % a region with enough characters exists
        end
    end
    for i = 1:numel(cand)
        if useSvm
            total(i) = cand(i).svm + 0.5 * cand(i).verify;
        else
            total(i) = cand(i).verify + 0.1 * cand(i).score / top;
        end
        bw = cand(i).box(3);  bc = cand(i).box(1:2) + cand(i).box(3:4) / 2;
        if o.SizeWeight ~= 0, total(i) = total(i) + o.SizeWeight * max(-1, min(1, log2(bw / 100))); end
        if o.CenterWeight ~= 0
            closeness = 1 - min(1, hypot((bc(1) - W0 / 2) / (W0 / 2), (bc(2) - H0 / 2) / (H0 / 2)) / sqrt(2));
            total(i) = total(i) + o.CenterWeight * closeness;
        end
        if o.Verify && ~(cand(i).nChars >= o.MinChars), total(i) = -Inf; end   % too few characters: sign, label, clutter
    end
    if all(isinf(total)) && o.Split && o.Verify && ~splitNow         % second try: cut touching characters apart (small bold night plates)
        splitNow = true;
        [~, oS] = sort([cand.svm], 'descend');                        % only the 10 best regions get the (slow) second look
        for i = 1:numel(cand), cand(i).nChars = NaN; end
        for i = oS(11:end), cand(i).nChars = 0;  cand(i).verify = 0; end
        continue
    end
    if all(isinf(total))                                                 % nothing with enough characters is left
        if useSvm, [~, best] = max([cand.svm]); end
        [~, qs] = min(abs(widths / W0 - cand(best).scale));
        dbg = fillDbg(dbg, scaleDbg{qs});
        dbg.all = cand;  dbg.chosen = best;
        dbg.rejected = true;  dbg.reason = 'characters';
        return
    end
    [~, best] = max(total);
    break
end

% debug images of the scale that produced the winner
[~, qs] = min(abs(widths / W0 - cand(best).scale));
dbg = fillDbg(dbg, scaleDbg{qs});
dbg.all = cand;
dbg.chosen = best;
dbg.versions = imgs;

% a region the plate SVM does not believe in is no plate: report "not found" instead
if ~isempty(o.PlateModel) && cand(best).svm < o.MinPlateScore
    dbg.rejected = true;  dbg.reason = 'svm';
    dbg.guess = cand(best).box;                             % the most plate-like region, for a low-confidence display
    return
end

crop = cropBox(imgs{cand(best).src}, cand(best).box);
b = cand(best).box;
r0 = max(1, round(b(2)));  c0 = max(1, round(b(1)));
plateImg = crop;
bbox = [c0, r0, size(crop, 2), size(crop, 1)];
end

% =========================================================================================
function dbg = fillDbg(dbg, sd)
dbg.scale = sd.scale;  dbg.edges = sd.edges;  dbg.blobs = sd.blobs;
dbg.candidates = sd.candidates;  dbg.scores = sd.scores;  dbg.working = sd.working;
end

function [cand, sd] = scaleCandidates(img, Wt, closePx, aspect)
% plate candidates found at one working width (boxes in original coordinates)
W0 = size(img, 2);
scale = Wt / W0;
I = imResize(img, scale, 'bilinear');
[H, W, ~] = size(I);
G = toGray(I);

Ge = grayTransform(G, 'stretch', 1, 99);                    % Module 1: enhance
Gs = smoothFilter(Ge, 'gaussian', 5, 1.0);

Gx = abs(spatialFilter(Gs, [-1 0 1; -2 0 2; -1 0 1]));     % vertical edges
Gx = Gx / max(max(Gx(:)), eps);
thr = max(otsuThreshold(Gx), 0.06);
E = Gx >= thr;

seClose = makeSE('rect', [3, closePx]);                     % join the strokes of neighbouring characters
seOpen  = makeSE('rect', [6, 13]);
M = morphOp(E, 'close', seClose);
M = morphOp(M, 'open', seOpen);
M = fillHoles(M);

[L, n] = labelComponents(M, 8);
props = componentProps(L, n);
bb = props.BoundingBox;
okShape = props.Aspect >= aspect(1) & props.Aspect <= aspect(2) & ...
          bb(:,4) >= 8 & bb(:,3) >= 45 & props.Extent >= 0.45;      % absolute pixel limits: small plates must survive
idx = find(okShape);

isColor = size(I, 3) == 3;
if isColor
    plateColour = colorSegment(I, 'HSV', 'white') | colorSegment(I, 'HSV', 'yellow');
end
cand = struct('box', {}, 'score', {}, 'scale', {}, 'verify', {});
score = zeros(numel(idx), 1);
for k = 1:numel(idx)
    b = bb(idx(k), :);
    r = b(2):b(2)+b(4)-1;  c = b(1):b(1)+b(3)-1;
    edgeDensity = mean(mean(E(r, c)));
    [~, ~, eta] = otsuThreshold(Gs(r, c));                  % bimodal (text on plate)?
    aspectScore = exp(-((props.Aspect(idx(k)) - 6) / 4)^2);
    colourFrac = 1;
    if isColor, colourFrac = 0.3 + mean(mean(plateColour(r, c))); end
    score(k) = edgeDensity * eta * aspectScore * colourFrac;

    padX = round(0.06 * b(3));  padY = round(0.35 * b(4));  % blob = text row only; add the plate margin
    x0 = max(1, b(1) - padX);  x1 = min(W, b(1) + b(3) - 1 + padX);
    y0 = max(1, b(2) - padY);  y1 = min(H, b(2) + b(4) - 1 + padY);
    wb = [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
    cand(end+1) = struct('box', wb / scale, 'score', score(k), 'scale', scale, 'verify', NaN); %#ok<AGROW>
end
sd = struct('scale', scale, 'edges', E, 'blobs', M, 'candidates', bb(idx, :), 'scores', score, 'working', I);
end

function cand = chainCandidates(img, Wt, offsets)
% Rows of character-sized blobs: threshold locally, label the blobs, keep those that
% look like characters, and join blobs of similar height that follow each other on a line.
scale = Wt / size(img, 2);
I = imResize(img, scale, 'bilinear');
Gs = smoothFilter(toGray(I), 'gaussian', 3, 0.8);
[H, W] = size(Gs);
cand = struct('box', {}, 'score', {}, 'scale', {}, 'verify', {});
for pc = 1:2 * numel(offsets)                                  % dark / bright characters, thin and thick strokes (a higher offset
    pol = {'dark', 'bright'};  pol = pol(1 + mod(pc - 1, 2));  % keeps blurred characters of a night plate apart)
    BW = adaptiveThreshold(Gs, 31, offsets(ceil(pc / 2)), pol{1});
    [L, n] = labelComponents(BW, 8);
    props = componentProps(L, n);
    bb = props.BoundingBox;
    h = bb(:,4);  w = bb(:,3);
    ok = h >= 10 & h <= 90 & w >= 3 & w <= 1.4 * h & props.Area ./ (w .* h) >= 0.2 & ...
         bb(:,1) > 1 & bb(:,2) > 1 & bb(:,1) + w < W & bb(:,2) + h < H;
    idx = find(ok);
    if numel(idx) < 4, continue; end
    if numel(idx) > 3000                                      % keep the largest blobs only
        [~, o] = sort(props.Area(idx), 'descend');  idx = idx(o(1:3000));
    end
    x = bb(idx,1);  y = bb(idx,2);  w = bb(idx,3);  h = bb(idx,4);
    yc = y + h / 2;  xr = x + w;
    dh  = abs(h - h.') ./ max(h, h.');                         % similar height
    dy  = abs(yc - yc.') ./ ((h + h.') / 2);                   % on one line
    gap = x.' - xr;                                            % gap(i,j): left of j minus right of i
    A = dh <= 0.35 & dy <= 0.3 & gap >= -0.25 * h & gap <= 2.0 * h;
    A = A | A.';
    lab = conncomp(graph(A));
    cnt = accumarray(lab(:), 1);
    for g = find(cnt(:).' >= 4 & cnt(:).' <= 14)
        m = lab == g;
        mh = mean(h(m));
        if std(yc(m)) / mh > 0.9, continue; end                % rows may be tilted, but not scattered
        x0 = min(x(m));  x1 = max(xr(m));  y0 = min(y(m));  y1 = max(y(m) + h(m));
        px = 0.7 * mh;  py = 0.45 * mh;
        wb = [max(1, x0 - px), max(1, y0 - py), min(W, x1 + px) - max(1, x0 - px), min(H, y1 + py) - max(1, y0 - py)];
        cand(end+1) = struct('box', wb / scale, 'score', 1 + cnt(g) / 10, 'scale', scale, 'verify', NaN); %#ok<AGROW>
    end
end
end

function pen = regionPenalty(crop, box, sz, topZone, satPenalty)
% Two physical rules that the plate SVM cannot learn from a few photos (penalty of 2 in SVM score):
%  - a region touching the top or bottom edge of the image is cut off or is a camera overlay
%    (date/time stamps, counters), not a plate;
%  - a region that is mostly saturated blue or green is a road/shop sign board;
%  - a region whose centre lies in the top 'topZone' of the photo (soft penalty of 1, not 2);
%  - a region with more than 35 % saturated pixels (soft penalty 'satPenalty').
pen = 0;
H = sz(1);
if topZone > 0 && box(2) + box(4) / 2 < topZone * H           % centre in the top part of the photo: overhead sign, overlay
    pen = pen + 1;
end
if box(2) <= 0.02 * H || box(2) + box(4) >= 0.98 * H
    pen = pen + 2;
end
if satPenalty > 0 && mean(toGray(crop) > 0.97, 'all') > 0.35        % glare / burnt-out region
    pen = pen + satPenalty;
end
if size(crop, 3) == 3
    hsv = rgb2hsv(crop);
    hu = hsv(:,:,1);  sa = hsv(:,:,2);  va = hsv(:,:,3);
    board = sa > 0.45 & va > 0.25 & ((hu > 0.52 & hu < 0.72) | (hu > 0.25 & hu < 0.45));
    if mean(board(:)) > 0.45, pen = pen + 2; end
end
end

function c = refineWindow(c, img, pm, topZone, satPenalty, alts, rounds)
% local search around a sliding window: shift in x, then in y, then resize, keeping what the plate SVM
% (with the region penalties) likes best; the 128x32 window grid and the size steps of the image
% pyramid are coarse, so the best window often cuts a character off the plate
[H, W, ~] = size(img);
b = c.box;  best = c.svm;
    function s = score(q)
        q = [max(1, round(q(1))), max(1, round(q(2))), round(q(3)), round(q(4))];
        if q(1) + q(3) - 1 > W || q(2) + q(4) - 1 > H || q(3) < 16 || q(4) < 8, s = -Inf;  return; end
        crop = img(q(2):q(2)+q(4)-1, q(1):q(1)+q(3)-1, :);
        s = plateScore(pm, crop);
        for a = 1:numel(alts), s = max(s, plateScore(pm, alts{a}(q(2):q(2)+q(4)-1, q(1):q(1)+q(3)-1, :))); end
        s = s - regionPenalty(crop, q, [H W], topZone, satPenalty);
    end
x0 = b;
szs = [0.9 1.1];  if rounds > 1, szs = [0.8 0.9 1.1 1.25]; end
for rd = 1:rounds
    before = best;
    b = x0;
    for dx = -0.2:0.025:0.2                                 % horizontal shift
        q = [b(1) + dx * b(3), b(2), b(3), b(4)];  s = score(q);
        if s > best, best = s;  x0 = q; end
    end
    b = x0;
    for dy = [-0.2 -0.1 0.1 0.2]                            % vertical shift
        q = [b(1), b(2) + dy * b(4), b(3), b(4)];  s = score(q);
        if s > best, best = s;  x0 = q; end
    end
    b = x0;
    for sc = szs                                            % size change about the centre
        q = [b(1) - (sc - 1) * b(3) / 2, b(2) - (sc - 1) * b(4) / 2, sc * b(3), sc * b(4)];  s = score(q);
        if s > best, best = s;  x0 = q; end
    end
    if best <= before + 1e-9, break; end
end
if best > c.svm
    c.box = [max(1, round(x0(1))), max(1, round(x0(2))), round(x0(3)), round(x0(4))];
    c.svm = best;
end
end

function c = checkCandidate(c, imgs, minChars, cv, split)
% cut characters out of a candidate (fast settings; the full tilt search if too few) and store the
% plate-likeness of the row (c.verify) and the number of characters (c.nChars); with a character-validity
% SVM a row of streaks or blobs counts as 0 characters. If the photo gives fewer than minChars characters, the
% other versions of it (equalised copy of a dark photo) are tried; c.src is the version that is used.
crop = cropBox(imgs{1}, c.box);
if size(crop, 1) < 8 || size(crop, 2) < 16, c.nChars = 0;  return; end
[n, v] = countChars(crop, minChars, cv, split);
src = 1;
for a = 2:numel(imgs)
    if n >= minChars, break; end
    [n3, v3] = countChars(cropBox(imgs{a}, c.box), minChars, cv, split);
    if n3 > n, n = n3;  v = v3;  src = a; end
end
c.verify = v;  c.nChars = n;  c.src = src;
end

function [n, v] = countChars(crop, minChars, cv, split)
[ch, ~, ~, v] = segmentPlateBest(crop, 'Mode', 'fast', 'Split', split, 'MinChars', minChars, 'Rescue', 'light');
n = numel(ch);
if n >= 1 && ~charsLookValid(cv, ch), n = 0;  v = 0; end
if n < minChars                                              % a tilted plate may need the tilt search
    [ch2, ~, ~, v2] = segmentPlateBest(crop, 'Mode', 'full', 'Split', split, 'MinChars', minChars, 'Rescue', 'light');
    n2 = numel(ch2);
    if n2 >= 1 && ~charsLookValid(cv, ch2), n2 = 0;  v2 = 0; end
    if n2 > n, n = n2;  v = v2; end
end
end

function crop = cropBox(img, b)
[H, W, ~] = size(img);
r = max(1, round(b(2))):min(H, round(b(2) + b(4) - 1));
c = max(1, round(b(1))):min(W, round(b(1) + b(3) - 1));
crop = img(r, c, :);
end

function v = boxIou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end
