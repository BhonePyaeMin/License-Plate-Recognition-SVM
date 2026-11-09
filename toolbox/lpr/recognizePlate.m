function res = recognizePlate(img, model, varargin)
%RECOGNIZEPLATE  Full pipeline: photo -> plate location -> characters -> SVM -> text.
%   res = RECOGNIZEPLATE(img, model, 'Name', value, ...)
%   img   : RGB or gray image (uint8 or double)
%   model : struct from TRAINLPRMODEL (fields svm, charset)
%   Options: 'Format'    optional layout such as 'LLL DDDD' (L = letter, D = digit,
%                        space = gap). When given, every character is classified
%                        only among the allowed type, which removes O/0, I/1, B/8
%                        style confusions.
%            'Plate'     pass an already cropped plate image to skip detection
%            'Polarity'  'auto' | 'dark' | 'bright' (character colour)
%            'SegOptions' cell of extra SEGMENTCHARS options ('Strategies', 'HeightRange')
%            'Exposure'  'auto' (default) | 'off': dark, bright or flat photos are repaired by
%                        NORMALIZEEXPOSURE before detection; normal photos are not touched
%            'PlateOnly' 'auto' (default) | 'on' | 'off': a photo that is itself a close-up of a
%                        plate (width/height between 1.6 and 9 and a row of characters
%                        filling it) is read directly, without searching for the plate.
%                        'on' forces it, 'off' always searches.
%            'MinChars'  fewer separable characters than this (default 4) is not a plate:
%                        found = false, res.reason says why (a route label such as "8C" on a sign has 2-3)
%            'MinConf'   mean vote confidence of the character SVM below this: not found (default 0 = off)
%            'ROI'       [x y w h]: only this part of the photo (one car, see PICKCARROI) is searched.
%                        The crop is processed with 'PlateOnly','off' (a car crop can look like a plate
%                        close-up) and a more lenient plate-SVM threshold (-1.2); res.bbox / res.guess
%                        are given in the coordinates of the full photo.
%            'MinPlateWidth' a plate found by the search that is narrower than this many pixels
%                        (default 40) is not read: found = false, res.reason = 'plate too small (W px)' and its box is returned
%                        in res.guess. Plates under 90 px are read but unreliable (the GUI warns). It was 90 before: on the 16 held-out photos
%                        shrunk to 25 % (plates of 40 to 70 px) 90 read 3 plates exactly (28.7 % of the characters), 40 reads 6 (59.1 %); at 40 % and on
%                        night photos the two limits give the same result
%            'Rectify'   'auto' (default) | 'off' | 'force': a plate seen at an angle is straightened
%                        (RECTIFYPLATE: four corners -> homography -> 240x80 rectangle) and read as well.
%                        'auto' uses the straightened plate when its outline is plate-like, clearly
%                        distorted (res.rectInfo.distortion >= RectifyMin, default 4) and its row of
%                        characters is at least as plate-like as the original; 'force' always uses it
%                        when the outline is plate-like, 'off' never. res.rectified tells what was used.
%            'RectifySize' [rows cols] of the straightened plate (default [] = 80 rows, width from the
%                        aspect of the outline; [80 240] = the fixed size)
%            'Expand'    a plate found by the search is also read from a box that is wider by this fraction
%                        of its width on both sides (default 0 = off; try 0.2); the wider box is used when it
%                        yields more characters (at most 10) in a row that is not clearly less plate-like.
%                        Tried to repair boxes that cut off the first or last character: no gain on the
%                        photos (car_07 and car_06 unchanged, car_01 slightly worse), so it is off.
%            'NightSearch' true (default): a dark photo (repaired by NORMALIZEEXPOSURE) is also searched in a locally
%                        equalised copy (CLAHE 8 x 8 tiles, clip 3), because a plate lit by the tail lights can hide in the
%                        glare of the global repair
%            'SmallBoost' 160 (default) | width in pixels (0 = off): a plate crop narrower than this is enlarged with bicubic
%                        interpolation to about this width and sharpened (unsharp masking) before its characters are cut out; the
%                        crop-level version of the filter chain "Resize x2 + Unsharp masking" of the situation "Small or far plate".
%                        Measured on the held-out photos (dev models): shrunk to 40 %: 4 -> 7 plates of 16 (characters 59.0 -> 64.1 %),
%                        clean photos unchanged (8 of 16, 74.6 %), 220 px instead of 160 gave 5; bicubic segmentation alone cost 2 clean plates
%            'Split'     true (default): the segmentation may cut touching characters apart (small bold night plates)
%            'CharCheck' true (default): if the model has a character-validity SVM (model.charValid) the cut-out
%                        components must look like characters, otherwise found = false and res.reason says
%                        'characters look like streaks or noise' (a van, a wall, a grille)
%            'DetectOptions' cell of extra DETECTPLATE options. If model.plate exists
%                        (plate / not-plate SVM from TRAINPLATEMODEL) it is used to rank
%                        the candidate regions.
%   res fields: found (logical), text, bbox [x y w h], guess [x y w h] (when no plate was
%               accepted: the most plate-like region, low confidence), plate (RGB crop),
%               chars (cell of 32x32), conf (per character), detectDebug, segDebug,
%               reason (why found is false: 'no candidate region', 'plate score too low',
%               'no region with enough characters', 'no characters', 'only N characters',
%               'format mismatch', 'low confidence'; empty when a plate was read).

p = inputParser;
p.addParameter('Format', '');
p.addParameter('Plate', []);
p.addParameter('Polarity', 'auto');
p.addParameter('SegOptions', {});
p.addParameter('DetectOptions', {});
p.addParameter('Exposure', 'auto');
p.addParameter('PlateOnly', 'auto');
p.addParameter('MinChars', 4);
p.addParameter('MinConf', 0);
p.addParameter('ROI', []);
p.addParameter('MinPlateWidth', 40);
p.addParameter('Rectify', 'auto');
p.addParameter('RectifyMin', 4);
p.addParameter('RectifySize', []);
p.addParameter('Expand', 0);
p.addParameter('CharCheck', true);
p.addParameter('Split', true);
p.addParameter('NightSearch', true);
p.addParameter('SmallBoost', 160);
p.parse(varargin{:});
o = p.Results;

if ~isempty(o.ROI)                                         % one car chosen: search only inside it
    res = recognizeInROI(img, model, o.ROI, varargin);
    return
end

res = emptyResult();
img = toDouble(img);

if isempty(o.Plate)
    img0 = [];                                             % the photo before the exposure repair (searched too)
    if strcmpi(o.Exposure, 'auto')
        img0 = img;
        [img, expInfo] = normalizeExposure(img);
        if ~expInfo.applied, img0 = []; end
    end
    isCrop = false;  cropSeg = [];
    if ~strcmpi(o.PlateOnly, 'off')
        if strcmpi(o.PlateOnly, 'on')
            [chars0, boxes0, dbg0] = segmentChars(img, 'Polarity', o.Polarity, 'Strategies', {'otsu', 'adaptive'}, 'SearchAngle', true, o.SegOptions{:});
            cropSeg = struct('chars', {chars0}, 'boxes', boxes0, 'dbg', dbg0);  isCrop = ~isempty(chars0);
        else
            [isCrop, cropSeg] = isPlateCloseup(img, o.Polarity, o.SegOptions);
        end
    end
    if isCrop                                              % the photo is a plate close-up: read it directly
        res.bbox = [1 1 size(img, 2) size(img, 1)];  res.plate = img;
        res.chars = cropSeg.chars;  res.boxes = cropSeg.boxes;  res.segDebug = cropSeg.dbg;
        res = classify(res, model, o);
        return
    end
    dopt = o.DetectOptions;
    if isfield(model, 'plate') && ~isempty(model.plate) && ~any(strcmpi(dopt(1:2:end), 'PlateModel'))
        dopt = [dopt, {'PlateModel', model.plate}];
    end
    dopt = [dopt, {'Split', o.Split}];
    if ~isempty(img0), dopt = [dopt, {'Original', img0}]; end
    if ~isempty(img0) && o.NightSearch                       % dark photo: the plate may show up only after local equalisation
        dopt = [dopt, {'Extra', {localHistEqualize(img0, 8, 3)}}];
    end
    if o.CharCheck && isfield(model, 'charValid') && ~isempty(model.charValid) && ~any(strcmpi(dopt(1:2:end), 'CharModel'))
        dopt = [dopt, {'CharModel', model.charValid}];
    end
    [bbox, plate, res.detectDebug] = detectPlate(img, dopt{:});
    if isempty(bbox)
        res.guess = res.detectDebug.guess;                  % refused region (only when the SVM score was too low)
        switch res.detectDebug.reason
            case 'svm',        res.reason = 'plate score too low';
            case 'characters', res.reason = 'no region with enough characters';
            otherwise,         res.reason = 'no candidate region';
        end
        return
    end
    if bbox(3) < o.MinPlateWidth                           % located, but too small to read reliably
        res.guess = bbox;  res.plate = plate;
        res.reason = sprintf('plate too small (%d px)', round(bbox(3)));
        return
    end
    res.bbox = bbox;
else
    plate = toDouble(o.Plate);
    res.bbox = [1 1 size(plate, 2) size(plate, 1)];
end
res.plate = plate;
if o.SmallBoost > 0 && size(plate, 2) < o.SmallBoost, plate = boostPlate(plate, o.SmallBoost); end
cutChars = [];  cutBoxes = [];  cutDbg = [];
if isempty(o.Plate) && o.Expand > 0                         % a box that cuts a character off the plate end reads wrongly
    [plate, res.bbox, cutChars, cutBoxes, cutDbg] = expandCut(img, plate, res.bbox, o);
    res.plate = plate;
end

% several segmentations (default, tilt search, threshold sweep + wide tilt search): the one that gives
% the most plate-like row of characters wins (the default is kept unless another is clearly better)
if ~isempty(cutChars)
    chars = cutChars;  boxes = cutBoxes;  res.segDebug = cutDbg;
else
    [chars, boxes, res.segDebug] = segmentPlateBest(plate, 'Polarity', o.Polarity, 'SegOptions', o.SegOptions, 'Split', o.Split);
end
if ~strcmpi(o.Rectify, 'off')                              % plate seen at an angle: warp it upright and read that too
    [chars, boxes, res] = tryRectified(plate, chars, boxes, res, o);
end
res.chars = chars;  res.boxes = boxes;
if isempty(chars), res.reason = 'no characters';  return; end

res = classify(res, model, o);
end

function res = classify(res, model, o)
% read the segmented characters with the character SVM (optionally restricted by a layout);
% too few characters, a layout of another length or a low confidence mean "not a plate"
chars = res.chars;
if isempty(chars), res.reason = 'no characters';  return; end
if numel(chars) < o.MinChars
    res.reason = sprintf('only %d characters', numel(chars));  return
end
if o.CharCheck && isfield(model, 'charValid') && ~isempty(model.charValid)
    [okC, res.charValidity] = charsLookValid(model.charValid, chars);
    if ~okC
        res.reason = 'characters look like streaks or noise';  return
    end
end
fmt = strrep(o.Format, ' ', '');
if ~isempty(fmt) && numel(fmt) ~= numel(chars)
    res.reason = 'format mismatch';  return
end
hp = struct('cellSize', 8, 'nBins', 9, 'signed', false);          % features of the model (older models: unsigned HOG, 324 values)
if isfield(model, 'hog') && ~isempty(model.hog), hp = model.hog; end
X = zeros(numel(chars), numel(hogFeatures(chars{1}, hp.cellSize, hp.nBins, hp.signed)));
for k = 1:numel(chars)
    X(k, :) = hogFeatures(chars{k}, hp.cellSize, hp.nBins, hp.signed);
end
[pred, conf, ~, score] = svmPredict(model.svm, X);

if ~isempty(fmt)                                           % restrict classes by expected type
    isDigit = ismember(model.charset, '0':'9');
    for k = 1:numel(chars)
        s = score(k, :);
        if upper(fmt(k)) == 'D', s(~isDigit(model.svm.classes)) = -Inf;
        elseif upper(fmt(k)) == 'L', s(isDigit(model.svm.classes)) = -Inf; end
        [~, b] = max(s);
        pred(k) = model.svm.classes(b);
    end
end
if mean(conf) < o.MinConf
    res.reason = 'low confidence';  res.conf = conf;  return
end
res.text = model.charset(pred(:).');
res.conf = conf;
res.found = true;
end

function res = recognizeInROI(img, model, roi, args)
% run the normal pipeline on the chosen car only and move the boxes back into the full photo
img = toDouble(img);
[H, W, ~] = size(img);
x0 = max(1, round(roi(1)));  y0 = max(1, round(roi(2)));
x1 = min(W, x0 + round(roi(3)) - 1);  y1 = min(H, y0 + round(roi(4)) - 1);
keep = true(size(args));
for k = 1:2:numel(args) - 1
    if any(strcmpi(args{k}, {'ROI', 'PlateOnly'})), keep(k:k+1) = false; end
end
if x1 - x0 < 15 || y1 - y0 < 15
    res = emptyResult();  res.reason = 'ROI too small';  return
end
% inside a car the plate SVM may be more lenient (-1.2 instead of -0.5, the value RECOGNIZEPLATES uses): a
% region the user marked contains a plate, so a false alarm costs less than a missed small plate
a = args(keep);
k = find(strcmpi(a(1:2:end), 'DetectOptions'), 1);
if isempty(k), a = [a, {'DetectOptions', {'MinPlateScore', -1.2}}];
elseif ~any(strcmpi(a{2*k}(1:2:end), 'MinPlateScore')), a{2*k} = [a{2*k}, {'MinPlateScore', -1.2}]; end
res = recognizePlate(img(y0:y1, x0:x1, :), model, a{:}, 'PlateOnly', 'off');
off = [x0 - 1, y0 - 1, 0, 0];
if ~isempty(res.bbox), res.bbox = res.bbox + off; end
if ~isempty(res.guess), res.guess = res.guess + off; end
res.roi = [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
end

function res = emptyResult()
res = struct('found', false, 'text', '', 'bbox', [], 'plate', [], 'chars', {{}}, ...
             'conf', [], 'boxes', [], 'detectDebug', [], 'segDebug', [], 'guess', [], 'reason', '', ...
             'rectified', false, 'rect', [], 'rectInfo', [], 'charValidity', []);
end

function [chars, boxes, res] = tryRectified(plate, chars, boxes, res, o)
% perspective correction: cut the characters out of the straightened plate as well and decide which row to use
[rect, okR, info] = rectifyPlate(plate, 'OutSize', o.RectifySize);
res.rectInfo = info;
if ~okR, return; end
[chars2, boxes2, dbg2] = segmentPlateBest(rect, 'Polarity', o.Polarity, 'SegOptions', o.SegOptions, 'Split', o.Split);
if isempty(chars2), return; end
s1 = plateRowScore(boxes);  s2 = plateRowScore(boxes2);
switch lower(o.Rectify)
    case 'force', use = true;
    otherwise
        use = isempty(chars) || ...
              (info.distortion >= o.RectifyMin && numel(chars2) >= numel(chars) && s2 >= s1 - 0.05) || ...
              s2 > s1 + 0.15;
end
if use
    chars = chars2;  boxes = boxes2;
    res.segDebug = dbg2;  res.rectified = true;  res.rect = rect;
end
end

function [plate, bbox, chars2, boxes2, dbg2] = expandCut(img, plate, bbox, o)
% read the plate also from a box widened on both sides; keep it if it has more characters and the row is as good
[H, W, ~] = size(img);
[chars1, boxes1, dbg1] = segmentPlateBest(plate, 'Polarity', o.Polarity, 'SegOptions', o.SegOptions);
chars2 = chars1;  boxes2 = boxes1;  dbg2 = dbg1;                 % default: the original box and its reading
mx = o.Expand * bbox(3);
x0 = max(1, round(bbox(1) - mx));  x1 = min(W, round(bbox(1) + bbox(3) - 1 + mx));
if x1 - x0 + 1 <= bbox(3) + 4, return; end
big = img(bbox(2):min(H, bbox(2) + bbox(4) - 1), x0:x1, :);
[chars3, boxes3, dbg3] = segmentPlateBest(big, 'Polarity', o.Polarity, 'SegOptions', o.SegOptions);
if numel(chars3) > numel(chars1) && numel(chars3) <= 10 && numel(chars3) >= o.MinChars && ...
        plateRowScore(boxes3) >= plateRowScore(boxes1) - 0.05
    plate = big;  bbox = [x0, bbox(2), x1 - x0 + 1, size(big, 1)];
    chars2 = chars3;  boxes2 = boxes3;  dbg2 = dbg3;
end
end

function P = boostPlate(plate, target)
% enlarge a small plate crop to about 'target' pixels of width (at most 4 times) and sharpen it
plate = toDouble(plate);
k = min(4, target / size(plate, 2));
if k <= 1.05, P = plate;  return; end
P = imResize(plate, k, 'bicubic');
sg = 0.6 * k;
P = P + 1.0 * (P - spatialFilter(P, gaussianKernel(2 * ceil(3 * sg) + 1, sg), 'replicate'));
P = min(max(P, 0), 1);
end
