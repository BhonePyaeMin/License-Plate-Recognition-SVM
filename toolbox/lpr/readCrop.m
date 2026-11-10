function [out, unread, info] = readCrop(img, model, box, varargin)
%READCROP  Read the licence plates inside a rectangle cut out of a photo (the crop tool of the GUI).
%   [out, unread, info] = READCROP(img, model, box, 'Name', value, ...)
%   box = [x y w h] in pixels of img. The rectangle is cut out like the crop tool of a photo editor,
%   enlarged (a small crop up to 4 times, to about 700 px on its long side) and searched with
%   RECOGNIZEPLATES (every plate of the crop, also a crop around two cars; two working widths and no small-plate pass,
%   because the crop is enlarged already: that is 3 times faster than the whole-photo search). When that finds nothing, a
%   lenient single search (plate score -1.2, the value used for a car region of READCARS) follows.
%   The boxes of out and unread are returned in pixels of the ORIGINAL photo, so they can be drawn on it;
%   out(k).width is measured in the original photo and decides "reliable" (90 px or more).
%   Options: 'MinChars' (4)   'Split' (true)   'NightVision' (false)   'Target' (700, long side of the enlarged crop)
%            'MaxScale' (4)   'ChainWidths' ([700 1000])   'SmallPlates' (false)
%   info has the fields box (the clipped crop), scale (enlargement) and seconds.
%   A plate that is only 30 px wide in the photo stays unreadable however much it is enlarged: the pixels are not there.

p = inputParser;
p.addParameter('MinChars', 4);
p.addParameter('Split', true);
p.addParameter('NightVision', false);
p.addParameter('Target', 700);
p.addParameter('MaxScale', 4);
p.addParameter('ChainWidths', [700 1000]);
p.addParameter('SmallPlates', false);
p.parse(varargin{:});
o = p.Results;

t0 = tic;
img = toDouble(img);
[H, W, ~] = size(img);
x0 = max(1, round(box(1)));  y0 = max(1, round(box(2)));
x1 = min(W, x0 + round(box(3)) - 1);  y1 = min(H, y0 + round(box(4)) - 1);
out = struct('box', {}, 'text', {}, 'conf', {}, 'score', {}, 'width', {}, 'reliable', {}, 'lines', {}, 'charH', {}, 'chars', {}, 'charBoxes', {}, 'segPlate', {});
unread = struct('box', {}, 'score', {}, 'width', {});
info = struct('box', [x0, y0, x1 - x0 + 1, y1 - y0 + 1], 'scale', 1, 'seconds', 0);
if x1 - x0 < 20 || y1 - y0 < 12, return; end

crop = img(y0:y1, x0:x1, :);
k = min(o.MaxScale, max(1, o.Target / max(size(crop, 1), size(crop, 2))));
if k > 1.05, Z = imResize(crop, k, 'bicubic'); else, k = 1;  Z = crop; end
info.scale = k;

[out, unread] = recognizePlates(Z, model, 'Cars', false, 'MinChars', o.MinChars, 'Split', o.Split, 'NightVision', o.NightVision, ...
                          'ChainWidths', o.ChainWidths, 'SmallPlates', o.SmallPlates);
if isempty(out)                                            % lenient single search, as for a car region of READCARS
    try
        r = recognizePlate(Z, model, 'PlateOnly', 'off', 'Split', o.Split, 'MinChars', o.MinChars, 'DetectOptions', {'MinPlateScore', -1.2});
    catch
        r = [];
    end
    if ~isempty(r) && r.found && numel(r.text) >= o.MinChars && numel(r.text) <= 10 && ~isempty(r.bbox)
        segPlate = [];  if ~isempty(r.segDebug) && isfield(r.segDebug, 'plate'), segPlate = r.segDebug.plate; end
        sc = -1;
        try sc = r.detectDebug.all(r.detectDebug.chosen).svm; catch, end %#ok<CTCH>
        out(1) = struct('box', r.bbox, 'text', r.text, 'conf', mean(r.conf), 'score', sc, 'width', round(r.bbox(3)), 'reliable', r.bbox(3) >= 90, ...
                        'lines', 1, 'charH', 0, 'chars', {r.chars}, 'charBoxes', r.boxes, 'segPlate', segPlate);
    end
end

for q = 1:numel(out)                                       % back to the pixels of the original photo
    b = out(q).box;
    out(q).box = [x0 - 1 + b(1) / k, y0 - 1 + b(2) / k, b(3) / k, b(4) / k];
    out(q).width = round(out(q).box(3));
    out(q).reliable = out(q).box(3) >= 90;
    out(q).charH = out(q).charH / k;
end
for q = 1:numel(unread)
    b = unread(q).box;
    unread(q).box = [x0 - 1 + b(1) / k, y0 - 1 + b(2) / k, b(3) / k, b(4) / k];
    unread(q).width = round(unread(q).box(3));
end
info.seconds = toc(t0);
end
