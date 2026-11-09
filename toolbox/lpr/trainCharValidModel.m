function cv = trainCharValidModel(varargin)
%TRAINCHARVALIDMODEL  Train the "is this a character?" SVM that rejects streaks and blobs.
%   cv = TRAINCHARVALIDMODEL('Name', value, ...)
%   The character SVM names every shape: a thin slanted stripe on a van becomes "I" or "1" with 100 %
%   votes, so the vote share says nothing about whether the shape IS a character. This second, binary SVM
%   (HOG of the 32x32 normalised component, RBF kernel) answers exactly that question.
%     positives  real characters cut out of the photos' plates (jittered copies) + synthetic characters
%     negatives  components that SEGMENTPLATEBEST cuts out of regions that are NOT the plate (car bodies,
%                grilles, bumpers, trees, walls: all candidate regions of the photos that do not overlap
%                the true plate box) + shapes of synthetic road/shop signs, lights and clutter (not the
%                text-like negatives such as date stamps, which consist of real digits)
%   Options: 'Subset'  'dev' (default) | 'all' - which photos are used
%            'NSynth'  synthetic characters per class (default 40)   'Replicate' copies per real character (4)
%            'NNeg'    at most this many negative components (default 3000)   'C' (10)   'Seed' (7)
%            'SaveTo'  .mat file ('' = none)
%   cv.svm is a binary SVM; use CHARVALIDITY to score characters (> 0: looks like a character) and
%   CHARSLOOKVALID (cv.rule) to judge a whole row. TRAIN_CHAR_VALID puts the model into the model files.

p = inputParser;
p.addParameter('Subset', 'dev');
p.addParameter('Group', 'project');
p.addParameter('TopK', 25);
p.addParameter('NSynth', 40);
p.addParameter('Replicate', 4);
p.addParameter('NNeg', 3000);
p.addParameter('C', 10);
p.addParameter('Seed', 7);
p.addParameter('SaveTo', '');
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
rng(o.Seed);
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));

% ---- positives ------------------------------------------------------------------------------
[Xs, ~] = generateCharDataset(tpl, 1:size(tpl.variants, 1), o.NSynth, o.Seed);
S = collectRealChars('Subset', o.Subset, 'Group', o.Group);
Xr = zeros(0, size(Xs, 2));
for k = 1:numel(S.y)
    for r = 1:o.Replicate
        Xr(end+1, :) = hogFeatures(jitterChar(S.imgs(:, :, k), r == 1)); %#ok<AGROW>
    end
end
Xp = [Xs; Xr];

% ---- negatives: components of the non-plate regions of the photos -----------------------------------
C = collectPlateCandidates([], 'Subset', o.Subset, 'Labels', 'location', 'Group', o.Group, 'TopK', o.TopK);
neg = find(C.y < 0);
neg = neg(randperm(numel(neg)));
Xn = zeros(0, size(Xs, 2));
cache = struct('name', "", 'img', []);
for q = 1:numel(neg)
    if size(Xn, 1) >= o.NNeg, break; end
    k = neg(q);
    if cache.name ~= C.photo(k)
        cache.name = C.photo(k);
        cache.img = normalizeExposure(toDouble(imread(fullfile(root, 'images', 'real', C.photo(k)))));
    end
    b = C.box(k, :);
    crop = cache.img(b(2):min(end, b(2) + b(4) - 1), b(1):min(end, b(1) + b(3) - 1), :);
    if size(crop, 1) < 8 || size(crop, 2) < 16, continue; end
    ch = segmentPlateBest(crop, 'Mode', 'fast');
    for j = 1:min(numel(ch), 6)
        Xn(end+1, :) = hogFeatures(ch{j}); %#ok<AGROW>
    end
end
nReal = size(Xn, 1);
% synthetic sign / light / clutter shapes (kinds 2, 4, 6, 7, 9 of MAKEHARDNEGATIVES: no real text)
[~, patches] = makeHardNegatives(tpl, 450);
for k = 1:numel(patches)
    if ~ismember(mod(k - 1, 9) + 1, [2 4 6 7 9]), continue; end
    ch = segmentPlateBest(patches{k}, 'Mode', 'fast');
    for j = 1:min(numel(ch), 4)
        Xn(end+1, :) = hogFeatures(ch{j}); %#ok<AGROW>
    end
end

X = [Xp; Xn];
y = [ones(size(Xp, 1), 1); -ones(size(Xn, 1), 1)];
kp.type = 'rbf';
kp.gamma = 1 / (size(X, 2) * max(var(X(:)), eps));
fprintf('char-validity SVM: %d positives (%d synthetic, %d real), %d negatives (%d from photos, %d synthetic shapes)\n', ...
    size(Xp, 1), size(Xs, 1), size(Xr, 1), size(Xn, 1), nReal, size(Xn, 1) - nReal);
m = svmTrainBinary(X, y, o.C, kp);
cv.svm = struct('SV', X(m.idx, :), 'coef', m.coef, 'b', m.b, 'kernel', kp);
cv.rule = struct('minMean', 0.2, 'minShare', 0.6);          % see CHARSLOOKVALID
cv.report = struct('nPos', size(Xp, 1), 'nNeg', size(Xn, 1), 'nSV', numel(m.idx), 'subset', o.Subset);
fprintf('  %d support vectors\n', numel(m.idx));
if ~isempty(o.SaveTo), save(o.SaveTo, 'cv'); end
end

function N = jitterChar(N, keepOriginal)
% small random distortion of a normalised 32 x 32 character (first copy unchanged)
if keepOriginal, return; end
N = geometricTransforms(N, 'rotate', (rand - 0.5) * 12, 'bilinear');
N = geometricTransforms(N, 'shear', (rand - 0.5) * 0.2, 0, 'bilinear');
N = geometricTransforms(N, 'scale', 0.9 + 0.2 * rand, 0.9 + 0.2 * rand, 'bilinear');
N = normalizeChar(N > 0.45, 32);
end
