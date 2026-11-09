function pm = trainPlateModel(model, varargin)
%TRAINPLATEMODEL  Train the plate / not-plate SVM that ranks candidate regions.
%   pm = TRAINPLATEMODEL(model, 'Name', value, ...)
%   Positive examples: candidate regions of the real 'dev' photos that the character
%   SVM could read (see COLLECTPLATECANDIDATES), each also cut out again with small
%   random shifts and scale changes, plus synthetic plates from RENDERPLATE.
%   Negative examples: all other candidates of the real photos (headlights, grilles,
%   signs, bumpers, ... : the clutter that really competes with plates), random
%   background patches, and synthetic hard negatives (MAKEHARDNEGATIVES: date/time
%   stamps, road signs, lights, sky and road clutter).
%   Options: 'Subset' 'dev' (default; 'all' for the final model)   'Jitter' copies per
%            positive (default 6)   'NSynthetic' synthetic plates (default 200)
%            'C' (default 10)   'SaveTo' (default models/plate_svm.mat)   'Seed' (7)
%            'Group' 'project' (default) | 'openalpr' | 'all' (SELECTREALPHOTOS)   'TopK' candidates per photo (default 25)
%            'MineNeg' / 'MinePos' window negatives / positives per photo while mining (60 / 10)
%            'MaxSamples' upper limit of the training samples (default 9000: memory of the n x n kernel matrix)
%            'Refresh' true: collect the candidate regions again instead of using the cache
%            'Labels' 'read' (default) | 'location': how the candidate regions are labelled, see
%                     COLLECTPLATECANDIDATES
%            'NightFraction' share of the synthetic plates that get a night look (default 0.25):
%                     gamma 1.8-3 and darkening, a red tail-light or white head-light glow over
%                     the plate, strong noise, small motion blur, and plates with light characters
%                     on a dark plate as well as dark characters on a light plate
%            'NHard'  synthetic hard negatives (default 450; nine kinds, see MAKEHARDNEGATIVES)
%            'Mine'   true: after a first training run, slide windows over the photos
%                     (SLIDINGPLATECANDIDATES, plate boxes of images/real/plate_boxes.csv) and add the
%                     windows that fit the plate as positives and the highest-scoring windows that miss
%                     it as hard negatives, then train again (needs 'Labels','location')
%   pm.svm: binary SVM (SV, coef, b, kernel).  Use PLATESCORE to evaluate it.

p = inputParser;
p.addParameter('Subset', 'dev');
p.addParameter('Group', 'project');
p.addParameter('TopK', 25);
p.addParameter('MineNeg', 60);
p.addParameter('MinePos', 10);
p.addParameter('MaxSamples', 9000);
p.addParameter('Jitter', 6);
p.addParameter('NSynthetic', 200);
p.addParameter('NHard', 450);
p.addParameter('C', 10);
p.addParameter('SaveTo', 'default');
p.addParameter('Seed', 7);
p.addParameter('Refresh', false);
p.addParameter('Labels', 'read');
p.addParameter('Mine', false);
p.addParameter('NightFraction', 0.25);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if strcmp(o.SaveTo, 'default'), o.SaveTo = fullfile(root, 'models', 'plate_svm.mat'); end
rng(o.Seed);
C = collectPlateCandidates(model, 'Subset', o.Subset, 'Refresh', o.Refresh, 'Labels', o.Labels, 'Group', o.Group, 'TopK', o.TopK);
X = C.X;  y = C.y;

% ---- jittered copies of the real positives ---------------------------------------------
pos = find(C.y > 0);
Xj = zeros(0, size(X, 2));
for q = 1:numel(pos)
    img = normalizeExposure(toDouble(imread(fullfile(root, 'images', 'real', C.photo(pos(q))))));
    b = C.box(pos(q), :);
    for r = 1:o.Jitter
        s = 0.85 + 0.3 * rand;                                  % size change
        cx = b(1) + b(3)/2 + (rand - 0.5) * 0.12 * b(3);        % centre shift
        cy = b(2) + b(4)/2 + (rand - 0.5) * 0.25 * b(4);
        w = b(3) * s;  h = b(4) * (0.85 + 0.3 * rand);
        rr = max(1, round(cy - h/2)):min(size(img, 1), round(cy + h/2));
        cc = max(1, round(cx - w/2)):min(size(img, 2), round(cx + w/2));
        if numel(rr) < 8 || numel(cc) < 16, continue; end
        Xj(end+1, :) = plateFeatures(img(rr, cc, :)); %#ok<AGROW>
    end
end

% ---- synthetic plates (positives) ----------------------------------------------------------
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
Xs = zeros(o.NSynthetic, size(X, 2));
for k = 1:o.NSynthetic
    v = randi(size(tpl.variants, 1));
    night = rand < o.NightFraction;
    styles = {'white', 'yellow', 'dark'};
    if night, st = styles{randi(3)}; else, st = ''; end                % night plates: both polarities
    [pl, ~] = renderPlate(randomPlateText(), tpl, v, 'Height', 60 + randi(50), 'Style', st);
    pl = geometricTransforms(pl, 'rotate', (rand - 0.5) * 16, 'bilinear');
    pl = geometricTransforms(pl, 'shear', (rand - 0.5) * 0.3, 0, 'bilinear');
    sg = 0.3 + 1.5 * rand;
    pl = spatialFilter(pl, gaussianKernel(2*ceil(3*sg) + 1, sg));
    pl = min(max(pl + 0.04 * rand * randn(size(pl)), 0), 1);
    if night, pl = nightLook(pl); end
    % crop: plate plus a little of the surroundings
    [h, w, ~] = size(pl);
    m = round(0.05 * h);
    Xs(k, :) = plateFeatures(pl(max(1, 1 + round(rand * m)):end, max(1, 1 + round(rand * m)):end, :));
end

% ---- random background negatives -------------------------------------------------------------------
phs = unique(C.photo);
Xn = zeros(0, size(X, 2));
for q = 1:numel(phs)
    img = normalizeExposure(toDouble(imread(fullfile(root, 'images', 'real', phs(q)))));
    [H, W, ~] = size(img);
    for r = 1:4
        w = round(W * (0.08 + 0.2 * rand));  h = round(w / (2.5 + 3 * rand));
        x0 = randi(max(1, W - w));  y0 = randi(max(1, H - h));
        Xn(end+1, :) = plateFeatures(img(y0:y0 + h - 1, x0:x0 + w - 1, :)); %#ok<AGROW>
    end
end

% ---- synthetic hard negatives: overlay text, signs, lights ------------------------------------
Xh = makeHardNegatives(tpl, o.NHard);

Xall = [X; Xj; Xs; Xn; Xh];
yall = [y; ones(size(Xj, 1) + size(Xs, 1), 1); -ones(size(Xn, 1) + size(Xh, 1), 1)];
fprintf('plate SVM: %d positives (%d real, %d jittered, %d synthetic), %d negatives (%d synthetic hard)\n', ...
    sum(yall > 0), sum(y > 0), size(Xj, 1), size(Xs, 1), sum(yall < 0), size(Xh, 1));
kp.type = 'rbf';
kp.gamma = 1 / (size(Xall, 2) * max(var(Xall(:)), eps));
m = svmTrainBinary(Xall, yall, o.C, kp);
pm.svm = struct('SV', Xall(m.idx, :), 'coef', m.coef, 'b', m.b, 'kernel', kp);
if o.Mine
    PB = readtable(fullfile(root, 'images', 'real', 'plate_boxes.csv'), 'TextType', 'string');
    Xp = zeros(0, size(Xall, 2));  Xm = zeros(0, size(Xall, 2));
    for q = 1:numel(phs)
        g = PB{PB.file == phs(q), {'x', 'y', 'w', 'h'}};
        if isempty(g), continue; end
        img = normalizeExposure(toDouble(imread(fullfile(root, 'images', 'real', phs(q)))));
        [~, mn] = slidingPlateCandidates(img, pm, 'GT', g(1, :), 'MinScore', -0.8, 'NPos', o.MinePos, 'NNeg', o.MineNeg);
        Xp = [Xp; mn.Xpos];  Xm = [Xm; mn.Xneg]; %#ok<AGROW>
        fprintf('  mining %s: %d window positives, %d hard negatives\n', phs(q), size(mn.Xpos, 1), size(mn.Xneg, 1));
    end
    nOld = size(Xall, 1);
    Xall = [Xall; Xp; Xm];
    yall = [yall; ones(size(Xp, 1), 1); -ones(size(Xm, 1), 1)];
    if size(Xall, 1) > o.MaxSamples                                % the SMO solver keeps an n x n kernel matrix: drop random negatives of the first round
        neg0 = find(yall(1:nOld) < 0);
        nDrop = min(numel(neg0), size(Xall, 1) - o.MaxSamples);
        drop = neg0(randperm(numel(neg0), nDrop));
        keep = true(size(Xall, 1), 1);  keep(drop) = false;
        Xall = Xall(keep, :);  yall = yall(keep);
        fprintf('  %d random negatives of the first round dropped (MaxSamples %d)\n', nDrop, o.MaxSamples);
    end
    fprintf('plate SVM after mining: %d positives, %d negatives\n', sum(yall > 0), sum(yall < 0));
    m = svmTrainBinary(Xall, yall, o.C, kp);
    pm.svm = struct('SV', Xall(m.idx, :), 'coef', m.coef, 'b', m.b, 'kernel', kp);
end
pm.report = struct('nPos', sum(yall > 0), 'nNeg', sum(yall < 0), 'nSV', numel(m.idx), 'subset', o.Subset);
fprintf('  %d support vectors\n', numel(m.idx));
if ~isempty(o.SaveTo), save(o.SaveTo, 'pm'); fprintf('Saved %s\n', o.SaveTo); end
end

function P = nightLook(P)
% a plate photographed at night: dark (gamma + darkening), a red tail-light or white head-light glow
% over it, small motion blur and strong sensor noise
P = P .^ (1.8 + 1.2 * rand);
P = P * (0.25 + 0.5 * rand);
[h, w, ~] = size(P);
[x, y] = meshgrid(1:w, 1:h);
cx = rand * w;  cy = rand * h;
glow = exp(-(((x - cx) / (0.5 * w)).^2 + ((y - cy) / (0.8 * h)).^2));
col = [1 0.15 0.1];  if rand < 0.5, col = [1 1 0.9]; end            % tail-light red or head-light white
amp = 0.15 + 0.45 * rand;
for ch = 1:3, P(:,:,ch) = min(1, P(:,:,ch) + amp * col(ch) * glow); end
L = 2 * randi(3) + 1;                                              % motion blur 3, 5 or 7 pixels
P = spatialFilter(P, ones(1, L) / L);
P = min(max(P + (0.04 + 0.08 * rand) * randn(size(P)), 0), 1);
end
