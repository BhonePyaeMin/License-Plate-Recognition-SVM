function [out, unread, cars] = readCars(img, model, out, unread, o)
%READCARS  Car by car: cut every car out of a road scene and read the cars that have no plate yet.
%   [out, unread, cars] = READCARS(img, model, out, unread, o)    (used by RECOGNIZEPLATES with 'Cars', true)
%   There is no car detector in base MATLAB, so the cars are proposed from what the plate search found:
%     - a car region around every plate that was read (plate width x 5.2 wide, x 4.4 high, the plate at two thirds of the height); at most 4 cars without a plate are searched,
%     - around every plate-like region that could not be read, and around the best weaker regions (o.Lenient, plate score -1.2 to 0),
%     - between every pair of red tail lights (two red blobs of the same size on one row with no third lamp between them: the rear of a car).
%   A region that shows the same car as an earlier one is dropped (two cars that both have a plate are never merged). A car without
%   a plate is cut out, enlarged (or, for a big photo, shrunk) to about 700 px width and searched with a lenient plate score (-1.2, the value used for a car that the
%   user picks); a plate that is found and read with 4 to 10 characters is added to out (small plates are marked unreliable). A plate
%   that was already read in the whole photo is not read again.
%   o is the option struct of RECOGNIZEPLATES (MinChars, MaxPlates are used).
%   cars(k) has box [x y w h] (the car region), plate (index in out, 0 = no plate found for this car) and source ('plate', 'region', 'lights').

[H, W, ~] = size(img);
cars = struct('box', {}, 'plate', {}, 'source', {});
for k = 1:numel(out), cars(end+1) = struct('box', carAround(out(k).box, H, W), 'plate', k, 'source', 'plate'); end %#ok<AGROW>
for k = 1:numel(unread), cars(end+1) = struct('box', carAround(unread(k).box, H, W), 'plate', 0, 'source', 'region'); end %#ok<AGROW>
if isfield(o, 'Lenient')
    for k = 1:size(o.Lenient, 1), cars(end+1) = struct('box', carAround(o.Lenient(k, :), H, W), 'plate', 0, 'source', 'region'); end %#ok<AGROW>
end
P = lampPairs(img);
for k = 1:size(P, 1), cars(end+1) = struct('box', P(k, :), 'plate', 0, 'source', 'lights'); end %#ok<AGROW>

keep = true(1, numel(cars));                                  % the same car seen twice: keep the first (plates read come first)
for i = 1:numel(cars)
    if ~keep(i), continue; end
    for j = i+1:numel(cars)
        if keep(j) && cars(j).plate == 0 && boxIou(cars(i).box, cars(j).box) > 0.3, keep(j) = false; end
    end
end
cars = cars(keep);
noPlate = find([cars.plate] == 0);
noPlate = noPlate(1:min(numel(noPlate), 4));
drop = false(1, numel(cars));
for q = noPlate(:).'
    b = round(cars(q).box);
    x0 = max(1, b(1));  x1 = min(W, b(1) + b(3) - 1);  y0 = max(1, b(2));  y1 = min(H, b(2) + b(4) - 1);
    if x1 - x0 < 40 || y1 - y0 < 30, drop(q) = true;  continue; end
    crop = img(y0:y1, x0:x1, :);
    k = min(4, max(0.5, 700 / size(crop, 2)));                % about 700 px wide: small cars are enlarged, the crop of a big photo is shrunk (speed)
    if k > 1.05, Z = imResize(crop, k, 'bicubic'); elseif k < 0.95, Z = imResize(crop, k, 'bilinear'); else, k = 1;  Z = crop; end
    try
        r = recognizePlate(Z, model, 'PlateOnly', 'off', 'Split', o.Split, 'MinChars', o.MinChars, 'DetectOptions', {'MinPlateScore', -1.2});
    catch
        continue
    end
    if ~r.found || numel(r.text) < o.MinChars || numel(r.text) > 10 || isempty(r.bbox), continue; end
    nb = [x0 - 1 + r.bbox(1) / k, y0 - 1 + r.bbox(2) / k, r.bbox(3) / k, r.bbox(4) / k];
    nb = [max(1, nb(1)), max(1, nb(2)), min(nb(3), W - nb(1)), min(nb(4), H - nb(2))];
    dup = 0;
    for j = 1:numel(out), if boxShare(nb, out(j).box) > 0.5, dup = j;  break; end, end
    if dup > 0
        cars(q).plate = dup;                                  % the plate of this car was read already
    elseif numel(out) < o.MaxPlates
        sc = -1;
        try sc = r.detectDebug.all(r.detectDebug.chosen).svm; catch, end %#ok<CTCH>
        out(end+1) = plateOut2(nb, r, sc);                    %#ok<AGROW>
        cars(q).plate = numel(out);
        for u = numel(unread):-1:1                            % a plate-like region that is now read is no longer "not read"
            if boxShare(unread(u).box, nb) > 0.5, unread(u) = []; end
        end
    end
end
cars = cars(~drop);
end

function s = plateOut2(box, res, score)
segPlate = [];  if ~isempty(res.segDebug) && isfield(res.segDebug, 'plate'), segPlate = res.segDebug.plate; end
h = 0;  if ~isempty(res.boxes), h = median(res.boxes(:, 4)) / 100 * box(4); end
s = struct('box', box, 'text', res.text, 'conf', mean(res.conf), 'score', score, 'width', round(box(3)), 'reliable', box(3) >= 90, ...
           'lines', 1, 'charH', h, 'chars', {res.chars}, 'charBoxes', res.boxes, 'segPlate', segPlate);
end

function b = carAround(p, H, W)
% the car that carries a plate of box p: 5.2 plate widths wide, 4.4 high, the plate centred and at two thirds of the height
cx = p(1) + p(3) / 2;
x0 = cx - 2.6 * p(3);  x1 = cx + 2.6 * p(3);
y0 = p(2) + p(4) / 2 - 2.9 * p(3);  y1 = y0 + 4.4 * p(3);
x0 = max(1, x0);  y0 = max(1, y0);  x1 = min(W, x1);  y1 = min(H, y1);
b = [x0, y0, x1 - x0, y1 - y0];
end

function P = lampPairs(img)
% rear of a car: two red tail lights of the same size on one row. Returns up to 4 car regions [x y w h], the biggest pairs first.
P = zeros(0, 4);
[H, W, C] = size(img);
if C ~= 3, return; end
s = min(1, 480 / W);
im = img;  if s < 1, im = imResize(img, s, 'bilinear'); end
hsv = rgb2hsv(min(max(im, 0), 1));
red = (hsv(:,:,1) < 0.04 | hsv(:,:,1) > 0.96) & hsv(:,:,2) > 0.55 & hsv(:,:,3) > 0.5;
[L, n] = labelComponents(red, 8);
if n < 2, return; end
pr = componentProps(L, n);
bb = pr.BoundingBox;
[h2, w2] = size(red);
ok = find(pr.Area >= 0.00025 * h2 * w2 & pr.Area <= 0.03 * h2 * w2 & bb(:,3) >= 0.8 * bb(:,4) & bb(:,3) <= 6 * bb(:,4));
cand = zeros(0, 5);                                           % [x y w h area] of the pair region, in the full photo
for ii = 1:numel(ok)
    for jj = ii+1:numel(ok)
        a = ok(ii);  c = ok(jj);
        if bb(a, 1) > bb(c, 1), t = a;  a = c;  c = t; end            % a is the left lamp
        d = (bb(c, 1) + bb(c, 3) / 2) - (bb(a, 1) + bb(a, 3) / 2);
        hm = max(bb(a, 4), bb(c, 4));  wm = max(bb(a, 3), bb(c, 3));
        sizeOk = pr.Area(a) / pr.Area(c) < 2.5 && pr.Area(c) / pr.Area(a) < 2.5;
        rowOk = abs((bb(a, 2) + bb(a, 4) / 2) - (bb(c, 2) + bb(c, 4) / 2)) < 0.6 * hm;
        between = false;                                                 % a third lamp on the same row between the two: they belong to different cars
        for t = ok(:).'
            if t == a || t == c, continue; end
            xt = bb(t, 1) + bb(t, 3) / 2;
            if xt > bb(a, 1) + bb(a, 3) / 2 && xt < bb(c, 1) + bb(c, 3) / 2 && abs(bb(t, 2) + bb(t, 4) / 2 - (bb(a, 2) + bb(a, 4) / 2)) < 0.6 * hm, between = true;  break; end
        end
        if sizeOk && rowOk && ~between && d > 2.5 * wm && d < 14 * wm
            cy = (bb(a, 2) + bb(a, 4) / 2 + bb(c, 2) + bb(c, 4) / 2) / 2;
            x0 = bb(a, 1) - 0.3 * d;  x1 = bb(c, 1) + bb(c, 3) + 0.3 * d;
            y0 = cy - 0.7 * d;  y1 = cy + 0.9 * d;
            cand(end+1, :) = [x0, y0, x1 - x0, y1 - y0, pr.Area(a) + pr.Area(c)]; %#ok<AGROW>
        end
    end
end
if isempty(cand), return; end
[~, o] = sort(cand(:, 5), 'descend');
cand = cand(o, :);
for i = 1:size(cand, 1)
    b = cand(i, 1:4) / s;
    b = [max(1, b(1)), max(1, b(2)), min(b(3), W - max(1, b(1))), min(b(4), H - max(1, b(2)))];
    if b(3) < 40 || b(4) < 30 || b(3) > 0.7 * W || b(4) > 0.7 * H, continue; end      % a car is not the whole photo (that is the pair of two different cars)
    dupl = false;
    for k = 1:size(P, 1), if boxIou(b, P(k, :)) > 0.3, dupl = true; end, end
    if ~dupl, P(end+1, :) = b; end %#ok<AGROW>
    if size(P, 1) >= 4, break; end
end
end

function v = boxShare(a, b)
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
