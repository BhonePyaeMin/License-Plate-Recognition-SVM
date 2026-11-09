function C = collectPlateCandidates(model, varargin)
%COLLECTPLATECANDIDATES  Candidate regions of the real photos with automatic labels.
%   C = COLLECTPLATECANDIDATES(model, 'Name', value, ...)
%   For every photo of the chosen subset, DETECTPLATE (without verification) proposes
%   candidate regions. Each region is read with the character SVM; it counts as a
%   __plate__ when the reading agrees with the known plate text well enough
%   (character accuracy >= 0.4), otherwise as a __non-plate__ (headlights, grille,
%   signs, ...). These labelled regions train the plate / not-plate SVM.
%   Options: 'Subset' 'dev' (default) | 'test' | 'all'     'TopK' candidates (default 25)
%            'Group'  'project' (default) | 'openalpr' | 'all': which photos (SELECTREALPHOTOS)
%            'Labels' 'read' (default: plate = the reading agrees with the true text) | 'location'
%                     (plate = the region overlaps the true plate box of images/real/plate_boxes.csv
%                     with IoU >= 0.4, non-plate = IoU < 0.2, regions in between are dropped; this
%                     also teaches the SVM plates that are hard to read, e.g. tilted ones; a photo
%                     without a row in plate_boxes.csv is labelled by reading, as in 'read')
%   C.X features (PLATEFEATURES)   C.y +1 / -1   C.photo   C.box [x y w h]   C.acc reading accuracy
%   The result is cached in models/plate_candidates_<subset>.mat.

p = inputParser;
p.addParameter('Subset', 'dev');
p.addParameter('Group', 'project');
p.addParameter('TopK', 25);
p.addParameter('Refresh', false);
p.addParameter('Labels', 'read');
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tag = '';  if strcmpi(o.Labels, 'location'), tag = '_loc'; end
if ~strcmpi(o.Group, 'project'), tag = [tag '_' lower(o.Group)]; end
cache = fullfile(root, 'models', sprintf('plate_candidates%s_%s.mat', tag, o.Subset));
if exist(cache, 'file') && ~o.Refresh
    S = load(cache);  C = S.C;  return
end
T = readtable(fullfile(root, 'images', 'real', 'labels.csv'), 'TextType', 'string', 'Delimiter', ',');
T = T(selectRealPhotos(T, o.Subset, o.Group), :);

C = struct('X', [], 'y', [], 'photo', strings(0, 1), 'box', [], 'acc', []);
if strcmpi(o.Labels, 'location')
    PB = readtable(fullfile(root, 'images', 'real', 'plate_boxes.csv'), 'TextType', 'string');
end
for k = 1:height(T)
    img = normalizeExposure(toDouble(imread(fullfile(root, 'images', 'real', T.file(k)))));   % as in RECOGNIZEPLATE
    truth = char(T.plate_text(k));
    [~, ~, dbg] = detectPlate(img, 'Verify', false, 'TopK', o.TopK);
    for i = 1:numel(dbg.all)
        b = dbg.all(i).box;
        r = max(1, round(b(2))):min(size(img, 1), round(b(2) + b(4) - 1));
        c = max(1, round(b(1))):min(size(img, 2), round(b(1) + b(3) - 1));
        crop = toDouble(img(r, c, :));
        g = [];
        if strcmpi(o.Labels, 'location'), g = PB{PB.file == T.file(k), {'x', 'y', 'w', 'h'}}; end
        if ~isempty(g)                                      % plate box known: label by position
            ov = boxIou([c(1), r(1), numel(c), numel(r)], g);
            if ov >= 0.2 && ov < 0.4, continue; end            % ambiguous: neither plate nor clutter
            acc = ov;  lab = 2 * (ov >= 0.4) - 1;
        else
            res = recognizePlate(img, model, 'Plate', crop);
            acc = max(0, 1 - editDistance(res.text, truth) / numel(truth));
            lab = 2 * (acc >= 0.4) - 1;
        end
        C.X(end+1, :) = plateFeatures(crop);  %#ok<AGROW>
        C.y(end+1, 1) = lab;  %#ok<AGROW>
        C.photo(end+1, 1) = T.file(k);  %#ok<AGROW>
        C.box(end+1, :) = [c(1), r(1), numel(c), numel(r)];  %#ok<AGROW>
        C.acc(end+1, 1) = acc;  %#ok<AGROW>
    end
    fprintf('%s: %d candidates, %d plate-like\n', T.file(k), numel(dbg.all), sum(C.y(strcmp(C.photo, T.file(k))) > 0));
end
save(cache, 'C');
end

function v = boxIou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end
