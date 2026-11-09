function [out, unread] = recognizePlates(img, model, varargin)
%RECOGNIZEPLATES  Find and read ALL licence plates in a photo (road scenes).
%   [out, unread] = RECOGNIZEPLATES(img, model, 'Name', value, ...)
%   Where RECOGNIZEPLATE returns only the best region, this function keeps every
%   candidate region that the plate SVM accepts, checks that a row of characters can
%   be cut out of it, reads each region with the character SVM and returns the plates
%   sorted by their score.
%   Options: 'MaxPlates' at most this many plates (default 12)
%            'MinScore'  minimum plate-SVM decision value (default -1.2: lenient, because the
%                        SVM scores small plates in busy scenes slightly below 0; on the real
%                        photos 0 gave 0.8 detections per photo and -1.2 gave 1.7, with the
%                        labelled plate read in 9 and 10 of 16 test photos. Raise it for fewer
%                        false boxes, lower it to find more plates)
%            'MinChars'  minimum number of characters in a region (default 4)
%            'Exposure'  'auto' (default) | 'off', see RECOGNIZEPLATE
%            'NightSearch' true (default): a dark photo is also searched in a locally equalised copy (see RECOGNIZEPLATE)
%            'Split'     true (default): touching characters may be cut apart when too few are found (see RECOGNIZEPLATE)
%            'SmallPlates' true (default): a second search with plate-SVM windows for plates of 48 and 66 pixels (of a 960 pixel copy of the
%                        photo) finds far plates of a big photo; it costs some seconds
%            'TwoLine'   true (default): a plate whose row has the shape of one line of a two-line plate (motorcycle,
%                        scooter, some countries) is searched for a second row above or below it; the text of both rows
%                        is joined with a space and out.lines is 2
%            'Rescue'    true (default): a plate-like region that could not be read is read again with wider crops, the
%                        frame of the plate trimmed off, the brightest colour channel and a threshold sweep; a reading of 4 to 10
%                        characters is listed with the plates (small plates are marked unreliable); only regions with a plate-SVM score of at
%                        least 'RescueMin' (default 0.2) are tried: weaker ones were tail lights and read as junk
%            'SecondLook' false (default) | true: small plates (under 90 px) and the best 4 unread plate-like regions are searched and read again in an
%                        enlarged (plate about 200 px wide) and sharpened copy of their surroundings; at most 'MaxSecond' (6) regions. Measured on 13 real plates
%                        of hard photos: mean character accuracy 56.7 -> 57.8 %, exact plates 2 -> 2, time per photo 58 -> 135 s: not worth it, so it is off.
%            'ROI'       [x y w h]: search only this part of the photo (boxes are returned in full-photo coordinates)
%   out is a struct array (empty if nothing was found) with the fields
%     box [x y w h] in the photo   text   conf (mean vote share)   score (plate SVM)
%     width (pixels)   reliable (width >= 90 px: smaller plates are read unreliably)
%     lines (1 or 2)   charH (height of the characters in pixels)
%   unread (second output) lists plate-like regions that could not be read (too small, blurred, glare): struct array
%   with box, score (plate SVM, at least -0.3) and width. On the 16 held-out test photos regions with a score >= -0.3
%   contained the plate in 14 of 16 photos, even when the photos were shrunk to 40 %, with about 1 false region per photo.
%   The model must contain a plate SVM (model.plate, see TRAIN_REAL_MODEL).

p = inputParser;
p.addParameter('MaxPlates', 12);
p.addParameter('MinScore', -1.2);
p.addParameter('MinChars', 4);
p.addParameter('Exposure', 'auto');
p.addParameter('ROI', []);
p.addParameter('NightSearch', true);
p.addParameter('Split', true);
p.addParameter('TwoLine', true);
p.addParameter('SmallPlates', true);
p.addParameter('Rescue', true);
p.addParameter('RescueMin', 0.2);
p.addParameter('SecondLook', false);
p.addParameter('MaxSecond', 6);
p.parse(varargin{:});
o = p.Results;
if ~isfield(model, 'plate') || isempty(model.plate)
    error('recognizePlates:model', 'This model has no plate SVM. Use models/lpr_svm_model_real.mat (train_real_model).');
end
unread = struct('box', {}, 'score', {}, 'width', {});
img = toDouble(img);
if ~isempty(o.ROI)                                         % one car (or area) chosen: search inside it only
    [H, W, ~] = size(img);
    x0 = max(1, round(o.ROI(1)));  y0 = max(1, round(o.ROI(2)));
    x1 = min(W, x0 + round(o.ROI(3)) - 1);  y1 = min(H, y0 + round(o.ROI(4)) - 1);
    [out, unread] = recognizePlates(img(y0:y1, x0:x1, :), model, 'MaxPlates', o.MaxPlates, 'MinScore', o.MinScore, ...
                          'MinChars', o.MinChars, 'Exposure', o.Exposure, 'NightSearch', o.NightSearch, 'Split', o.Split, 'TwoLine', o.TwoLine, 'Rescue', o.Rescue, 'RescueMin', o.RescueMin, 'SmallPlates', o.SmallPlates);
    for k = 1:numel(out), out(k).box = out(k).box + [x0 - 1, y0 - 1, 0, 0]; end
    for k = 1:numel(unread), unread(k).box = unread(k).box + [x0 - 1, y0 - 1, 0, 0]; end
    return
end
img0 = [];                                                 % the photo before the exposure repair (searched too)
if strcmpi(o.Exposure, 'auto')
    img0 = img;
    [img, expInfo] = normalizeExposure(img);
    if ~expInfo.applied, img0 = []; end
end

out = struct('box', {}, 'text', {}, 'conf', {}, 'score', {}, 'width', {}, 'reliable', {}, 'lines', {}, 'charH', {});
[isCrop, seg] = isPlateCloseup(img);                       % the photo itself is a plate close-up
if isCrop
    res = recognizePlate(img, model, 'Exposure', 'off');
    if res.found
        out(1) = struct('box', [1 1 size(img, 2) size(img, 1)], 'text', res.text, 'conf', mean(res.conf), 'score', Inf, ...
                        'width', size(img, 2), 'reliable', true, 'lines', 1, 'charH', 0);
    end
    return
end

cmodel = [];
if isfield(model, 'charValid'), cmodel = model.charValid; end            % streaks / blobs do not count as characters
extra = {};
if ~isempty(img0) && o.NightSearch, extra = {localHistEqualize(img0, 8, 3)}; end   % dark photo: also search an equalised copy
[~, ~, dbg] = detectPlate(img, 'PlateModel', model.plate, 'TopK', 40, 'VerifyTop', 15, 'Original', img0, 'Extra', extra, 'CharModel', cmodel, 'Split', o.Split, ...
                       'ChainWidths', [960 1440 2000], 'ChainOffsets', [0.05 0.15]);   % every region is read, so more candidates cannot push a plate out
cand = dbg.all;
if o.SmallPlates                                           % second search, only for small plates: its windows must not push the others out of the check
    [~, ~, dbg2] = detectPlate(img, 'PlateModel', model.plate, 'TopK', 40, 'VerifyTop', 15, 'Original', img0, 'Extra', extra, 'CharModel', cmodel, ...
                               'Split', o.Split, 'Methods', {'windows'}, 'WindowWidths', [48 66], 'WindowMin', -0.85, 'WindowTop', 12);
    if ~isempty(dbg2.all) && isfield(dbg2.all, 'nChars') && (isempty(cand) || isequal(fieldnames(cand), fieldnames(dbg2.all)))
        if isempty(cand), dbg = dbg2;  cand = dbg2.all; else, cand = [cand, dbg2.all]; end
    end
end
if isempty(cand), return; end
allCand = cand;                                            % every region of both searches (the unread list below)

% keep regions the SVM accepts and in which a plausible character row exists
keep = [cand.svm] >= o.MinScore & ([cand.verify] > 0.05 | [cand.svm] >= 0.3);   % a strong plate score is read even if its characters touch (rescue split)
cand = cand(keep);
[~, order] = sort([cand.svm] + 0.5 * [cand.verify], 'descend');
cand = cand(order);

used = false(1, numel(cand));
for i = 1:numel(cand)
    if used(i) || numel(out) >= o.MaxPlates, continue; end
    b = cand(i).box;
    for j = i+1:numel(cand)                                % suppress boxes that overlap a better one
        if ~used(j) && boxIou(b, cand(j).box) > 0.25, used(j) = true; end
    end
    r = max(1, round(b(2))):min(size(img, 1), round(b(2) + b(4) - 1));
    c = max(1, round(b(1))):min(size(img, 2), round(b(1) + b(3) - 1));
    src = img;                                             % the version of the photo in which its characters were found
    if isfield(dbg, 'versions') && isfield(cand, 'src') && cand(i).src <= numel(dbg.versions), src = dbg.versions{cand(i).src}; end
    res = recognizePlate(img, model, 'Plate', src(r, c, :), 'Exposure', 'off', 'Split', o.Split);
    if ~res.found || numel(res.text) < o.MinChars, continue; end
    out(end+1) = struct('box', [c(1), r(1), numel(c), numel(r)], 'text', res.text, ...
        'conf', mean(res.conf), 'score', cand(i).svm, 'width', numel(c), 'reliable', numel(c) >= 90, ...
        'lines', 1, 'charH', rowCharHeight(res, numel(r))); %#ok<AGROW>
end
if o.TwoLine, out = addSecondRows(out, img, model); end
out = dropNested(out);

% plate-like regions that could not be read: plate-SVM score >= -0.3, not overlapping a plate that was read
cand2 = allCand;
[~, o2] = sort([cand2.svm], 'descend');
for i = o2(:).'
    if cand2(i).svm < -0.3 || numel(unread) >= 6, break; end
    b = cand2(i).box;
    if b(3) < 16 || b(3) > 0.9 * size(img, 2), continue; end
    over = false;
    for k = 1:numel(out), if boxIou(b, out(k).box) > 0.2 || boxShare(b, out(k).box) > 0.5, over = true; break; end, end   % a region around or inside a read plate is that plate
    for k = 1:numel(unread), if boxIou(b, unread(k).box) > 0.2, over = true; break; end, end
    if ~over, unread(end+1) = struct('box', b, 'score', cand2(i).svm, 'width', round(b(3))); end %#ok<AGROW>
end

% last resort for those regions: wider crops, the plate frame trimmed off, the brightest colour channel, a level sweep
if o.Rescue && ~isempty(unread)
    keepU = true(1, numel(unread));
    for i = 1:numel(unread)
        if unread(i).score < o.RescueMin, continue; end                 % weaker regions are tail lights, grilles, stripes: reading them gives junk
        [res, bx] = rescueRead(img, model, unread(i).box);
        if isempty(res), continue; end
        out(end+1) = struct('box', bx, 'text', res.text, 'conf', mean(res.conf), 'score', unread(i).score, 'width', round(bx(3)), ...
                            'reliable', bx(3) >= 90, 'lines', 1, 'charH', rowCharHeight(res, bx(4))); %#ok<AGROW>
        keepU(i) = false;
    end
    unread = unread(keepU);
    out = dropNested(out);
end

% second look: small plates and unread plate-like regions are searched again in an enlarged, sharpened copy of their surroundings
if o.SecondLook
    [out, unread] = secondLook(img, model, out, unread, o);
    out = dropNested(out);
end
end

function [best, box] = rescueRead(img, model, b)
% read a plate-like region that the normal reading refused, with other crops and segmentation settings;
% the reading with the most characters (4 to 10, the characters must look like characters) wins
[H, W, ~] = size(img);
lv = [0.8 1 1.2 1.4];
V = {{}, ...
     {'Trim', 0.12, 'Levels', lv, 'LevelRegion', 'center', 'Select', 'row', 'SearchAngle', true}, ...
     {'Channel', 'max', 'Levels', lv, 'LevelRegion', 'center', 'Select', 'row'}, ...
     {'Trim', 0.12, 'Channel', 'max', 'Levels', lv, 'LevelRegion', 'center', 'Select', 'row', 'SearchAngle', true}};
best = [];  box = b;  bestKey = 0;
for pd = [0.15 0.3]
    pad = round(pd * b(4));
    x0 = max(1, floor(b(1) - pad));  x1 = min(W, ceil(b(1) + b(3) - 1 + pad));
    y0 = max(1, floor(b(2) - pad));  y1 = min(H, ceil(b(2) + b(4) - 1 + pad));
    if x1 - x0 < 20 || y1 - y0 < 8, continue; end
    crop = img(y0:y1, x0:x1, :);
    for v = 1:numel(V)
        res = recognizePlate(img, model, 'Plate', crop, 'Exposure', 'off', 'SegOptions', V{v}, 'Rectify', 'off');
        n = numel(res.text);
        if ~res.found || n < 4 || n > 10, continue; end
        key = n + mean(res.conf);
        if key > bestKey, bestKey = key;  best = res;  box = [x0, y0, x1 - x0 + 1, y1 - y0 + 1]; end
    end
end
end

function [out, unread] = secondLook(img, model, out, unread, o)
% The situation "Small or far plate" (enlarge 2 times + unsharp masking) read 10 of 13 real plates of a hard test set where
% no filter read 5. Here the same is done automatically, but only around the plates that need it: every small plate (under 90 px)
% and the best plate-like regions that could not be read. The surroundings (3.4 x 6 plate sizes) are enlarged so that the plate
% is about 200 px wide, sharpened, and searched and read again; a new reading replaces a small one that has fewer characters.
[H, W, ~] = size(img);
tg = zeros(0, 4);  isRead = false(0, 1);  who = zeros(0, 1);
for k = 1:numel(out)
    if out(k).width < 90, tg(end+1, :) = out(k).box;  isRead(end+1, 1) = true;  who(end+1, 1) = k; end %#ok<AGROW>
end
[~, ou] = sort([unread.score], 'descend');
for k = ou(1:min(numel(ou), 4))
    tg(end+1, :) = unread(k).box;  isRead(end+1, 1) = false;  who(end+1, 1) = k; end %#ok<AGROW>
tg = tg(1:min(size(tg, 1), o.MaxSecond), :);  isRead = isRead(1:size(tg, 1));  who = who(1:size(tg, 1));
dropU = false(1, numel(unread));
for t = 1:size(tg, 1)
    b = tg(t, :);
    x0 = max(1, floor(b(1) - 1.2 * b(3)));  x1 = min(W, ceil(b(1) + 2.2 * b(3)));
    y0 = max(1, floor(b(2) - 2.5 * b(4)));  y1 = min(H, ceil(b(2) + 3.5 * b(4)));
    k = min(4, max(2, 200 / b(3)));
    crop = imResize(img(y0:y1, x0:x1, :), k, 'bicubic');
    sg = 1.2;
    crop = min(max(crop + (crop - spatialFilter(crop, gaussianKernel(2 * ceil(3 * sg) + 1, sg), 'replicate')), 0), 1);
    r = recognizePlate(crop, model, 'Exposure', 'auto', 'MinPlateWidth', 0, 'PlateOnly', 'off', 'SmallBoost', 0);
    if ~r.found || numel(r.text) < o.MinChars || isempty(r.bbox), continue; end
    nb = [x0 - 1 + r.bbox(1) / k, y0 - 1 + r.bbox(2) / k, r.bbox(3) / k, r.bbox(4) / k];
    nb = [max(1, nb(1)), max(1, nb(2)), min(nb(3), W - nb(1)), min(nb(4), H - nb(2))];
    if isRead(t)
        if numel(r.text) < numel(out(who(t)).text) || boxShare(nb, out(who(t)).box) < 0.5, continue; end
        out(who(t)).text = r.text;  out(who(t)).conf = mean(r.conf);  out(who(t)).box = nb;  out(who(t)).width = round(nb(3));
        out(who(t)).reliable = nb(3) >= 90;
    else
        out(end+1) = struct('box', nb, 'text', r.text, 'conf', mean(r.conf), 'score', unread(who(t)).score, 'width', round(nb(3)), ...
                            'reliable', nb(3) >= 90, 'lines', 1, 'charH', rowCharHeight(r, nb(4) * k)); %#ok<AGROW>
        dropU(who(t)) = true;
    end
end
unread = unread(~dropU);
end

function h = rowCharHeight(res, cropH)
% height of the characters of a read row in photo pixels (the plate is resized to 100 rows for the segmentation)
h = 0;
if ~isempty(res.boxes), h = median(res.boxes(:, 4)) / 100 * cropH; end
end

function out = addSecondRows(out, img, model)
% Two-line plates (motorcycles, scooters): the plate search finds one row. Look for a second row of characters of the
% same height directly above or below it, in a window about as wide as the first row, and join the two readings.
[H, W, ~] = size(img);
for k = 1:numel(out)
    b = out(k).box;
    if out(k).lines > 1 || out(k).charH < 6 || b(3) / b(4) < 1.6 || b(3) / b(4) > 4.3, continue; end
    for dirn = [1 -1]
        if dirn > 0, win = [b(1) - 0.3 * b(3), b(2) + 0.75 * b(4), 1.6 * b(3), 1.4 * b(4)];
        else,        win = [b(1) - 0.3 * b(3), b(2) - 1.15 * b(4), 1.6 * b(3), 1.4 * b(4)]; end
        r = max(1, round(win(2))):min(H, round(win(2) + win(4) - 1));
        c = max(1, round(win(1))):min(W, round(win(1) + win(3) - 1));
        if numel(r) < 10 || numel(c) < 20, continue; end
        res = recognizePlate(img, model, 'Plate', img(r, c, :), 'Exposure', 'off', 'MinChars', 3, 'PlateOnly', 'off', 'Rectify', 'off');
        if ~res.found || numel(res.text) < 3 || numel(res.text) > 10 || isempty(res.boxes), continue; end
        s = numel(r) / 100;                                   % segmentation coordinates -> photo pixels
        cx0 = c(1) - 1 + min(res.boxes(:, 1)) * s;  cx1 = c(1) - 1 + max(res.boxes(:, 1) + res.boxes(:, 3)) * s;
        cy0 = r(1) - 1 + min(res.boxes(:, 2)) * s;  cy1 = r(1) - 1 + max(res.boxes(:, 2) + res.boxes(:, 4)) * s;
        h2 = median(res.boxes(:, 4)) * s;
        ov = min(cx1, b(1) + b(3)) - max(cx0, b(1));
        gap = abs((cy0 + cy1) / 2 - (b(2) + b(4) / 2));
        if h2 < 0.7 * out(k).charH || h2 > 1.4 * out(k).charH, continue; end          % characters of the same size
        if ov < 0.5 * min(cx1 - cx0, b(3)), continue; end                               % rows above each other
        if gap < 0.8 * out(k).charH || gap > 2.2 * out(k).charH, continue; end          % one row apart
        rowBox = [max(1, floor(cx0 - 0.1 * (cx1 - cx0))), max(1, floor(cy0 - 0.2 * h2)), ceil(1.2 * (cx1 - cx0)), ceil(cy1 - cy0 + 0.4 * h2)];
        if dirn > 0, txt = [out(k).text ' ' res.text]; else, txt = [res.text ' ' out(k).text]; end
        x0 = min(b(1), rowBox(1));  y0 = min(b(2), rowBox(2));
        x1 = max(b(1) + b(3), rowBox(1) + rowBox(3));  y1 = max(b(2) + b(4), rowBox(2) + rowBox(4));
        out(k).box = [x0, y0, x1 - x0, y1 - y0];  out(k).text = txt;  out(k).lines = 2;  out(k).width = round(x1 - x0);
        out(k).conf = mean([out(k).conf, mean(res.conf)]);
        out(k).reliable = out(k).width >= 90;
        break
    end
end
end

function out = dropNested(out)
% two read boxes that lie one inside the other (or share most of the smaller one) show the same plate: a wide box that
% swallowed the plate and the tail lights next to it, and a tight one. Keep the reading with more characters; on a tie
% the smaller box (a plate does not contain another plate).
n = numel(out);
drop = false(1, n);
for i = 1:n
    for j = i+1:n
        if drop(i) || drop(j), continue; end
        if boxShare(out(i).box, out(j).box) <= 0.6, continue; end
        ni = numel(out(i).text);  nj = numel(out(j).text);
        ai = prod(out(i).box(3:4));  aj = prod(out(j).box(3:4));
        if ni > nj || (ni == nj && ai <= aj), drop(j) = true; else, drop(i) = true; end
    end
end
out = out(~drop);
end

function v = boxShare(a, b)
% intersection area divided by the area of the smaller box
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
v = max(0, x2-x1) * max(0, y2-y1) / min(a(3)*a(4), b(3)*b(4));
end

function v = boxIou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end
