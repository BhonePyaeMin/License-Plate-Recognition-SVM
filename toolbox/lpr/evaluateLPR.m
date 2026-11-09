function R = evaluateLPR(model, varargin)
%EVALUATELPR  Measure the recognition pipeline on freshly generated synthetic scenes.
%   R = EVALUATELPR(model, 'Name', value, ...)
%   Options: 'N'      number of scenes (default 100)
%            'Hard'   difficulty 0..1 passed to MAKESCENE (default 0.5)
%            'Fonts'  'test' (default, fonts the SVM never saw) | 'train'
%            'Seed'   random seed (default 99)
%            'Figure' file name of a PNG with example results ('' = none)
%   Reported metrics
%     detection     plate box overlaps the true plate with IoU > 0.5
%     segmentation  number of segmented characters equals the true length
%     char accuracy 1 - edit distance / length, averaged over all scenes
%     plate accuracy exact match of the whole plate text
%       - without format  : plain 36-class SVM decision
%       - with format     : letters/digits restricted by the known layout
%   R is a struct with these numbers plus per-scene details.

p = inputParser;
p.addParameter('N', 100);
p.addParameter('Hard', 0.5);
p.addParameter('Fonts', 'test');
p.addParameter('Seed', 99);
p.addParameter('Figure', '');
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
if strcmpi(o.Fonts, 'test'), fonts = find(tpl.isTest); else, fonts = find(~tpl.isTest); end
rng(o.Seed);

N = o.N;
det = false(N,1);  seg = false(N,1);  ok1 = false(N,1);  ok2 = false(N,1);
cacc1 = zeros(N,1);  cacc2 = zeros(N,1);  tms = zeros(N,1);
pred1 = cell(N,1);  pred2 = cell(N,1);  truth = cell(N,1);  imgs = cell(N,1);  boxes = cell(N,1);
for k = 1:N
    [img, gt] = makeScene(tpl, fonts, 'Hard', o.Hard);
    truth{k} = gt.text;
    t0 = tic;
    r1 = recognizePlate(img, model);
    tms(k) = toc(t0);
    if ~isempty(r1.bbox)
        det(k) = iou(r1.bbox, gt.bbox) > 0.5;
        boxes{k} = r1.bbox;
    end
    pred1{k} = r1.text;
    seg(k) = r1.found && numel(r1.text) == numel(gt.text);
    ok1(k) = strcmp(r1.text, gt.text);
    cacc1(k) = max(0, 1 - editDistance(r1.text, gt.text) / numel(gt.text));
    if r1.found                                            % second decode with the known layout
        r2 = recognizePlate(img, model, 'Plate', r1.plate, 'Format', gt.format);
        pred2{k} = r2.text;
        ok2(k) = strcmp(r2.text, gt.text);
        cacc2(k) = max(0, 1 - editDistance(r2.text, gt.text) / numel(gt.text));
    else
        pred2{k} = '';
    end
    imgs{k} = img;
end

R.N = N;  R.hard = o.Hard;  R.fonts = o.Fonts;
R.detectionRate = mean(det);
R.segmentationRate = mean(seg);
R.charAccuracyNoFormat = mean(cacc1);
R.charAccuracyWithFormat = mean(cacc2);
R.plateAccuracyNoFormat = mean(ok1);
R.plateAccuracyWithFormat = mean(ok2);
R.secondsPerImage = mean(tms);
R.truth = truth;  R.predNoFormat = pred1;  R.predWithFormat = pred2;

fprintf('\nEvaluation on %d synthetic scenes (%s fonts, difficulty %.2f)\n', N, o.Fonts, o.Hard);
fprintf('  plate detection (IoU > 0.5)      : %5.1f %%\n', 100 * R.detectionRate);
fprintf('  correct number of characters     : %5.1f %%\n', 100 * R.segmentationRate);
fprintf('  character accuracy, no format    : %5.1f %%\n', 100 * R.charAccuracyNoFormat);
fprintf('  character accuracy, with format  : %5.1f %%\n', 100 * R.charAccuracyWithFormat);
fprintf('  exact plate match, no format     : %5.1f %%\n', 100 * R.plateAccuracyNoFormat);
fprintf('  exact plate match, with format   : %5.1f %%\n', 100 * R.plateAccuracyWithFormat);
fprintf('  time per image                   : %5.2f s\n', R.secondsPerImage);

if ~isempty(o.Figure)
    vis = get(0, 'DefaultFigureVisible');
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [30 30 1400 800]);
    for k = 1:min(12, N)
        ax = subplot(3, 4, k);
        showImage(ax, imgs{k});
        good = strcmp(pred1{k}, truth{k});
        if good, col = [0 0.55 0]; else, col = [0.8 0 0]; end
        title(ax, sprintf('truth %s | read %s', truth{k}, pred1{k}), 'Color', col, 'FontSize', 9);
        if ~isempty(boxes{k}), rectangle(ax, 'Position', boxes{k}, 'EdgeColor', 'r', 'LineWidth', 1.2); end
    end
    saveas(fig, o.Figure);
    close(fig);
    set(0, 'DefaultFigureVisible', vis);
end
end

function v = iou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end
