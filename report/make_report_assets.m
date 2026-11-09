function make_report_assets(sections)
%MAKE_REPORT_ASSETS  Regenerate every figure and measured number used in the project report.
%   >> cd report; make_report_assets            % all sections (about 6 minutes)
%   >> make_report_assets({'m1','m3'})          % only some sections
%   Sections: code, m1, m2, m3, svm, pipeline, sweep, real (and diagram = block diagram only).
%   Figures go to report/figures/*.png and the numbers to report/data/<section>.json;
%   build_report.js reads both, so nothing in the report is typed in by hand.

if nargin < 1, sections = {'code', 'm1', 'm2', 'm3', 'svm', 'pipeline', 'sweep', 'real'}; end
root = fileparts(fileparts(mfilename('fullpath')));
cd(root);
setup_toolbox;
ctx.root = root;
ctx.figDir = fullfile(root, 'report', 'figures');
ctx.dataDir = fullfile(root, 'report', 'data');
for d = {ctx.figDir, ctx.dataDir}
    if ~exist(d{1}, 'dir'), mkdir(d{1}); end
end
ctx.tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
rng(4);                                                    % same scene as demo_modules
[ctx.I, ctx.gt] = makeScene(ctx.tpl, find(ctx.tpl.isTest), 'Hard', 0.5);
ctx.G = toGray(ctx.I);
set(0, 'DefaultFigureVisible', 'off');

sec = struct('code', @sec_code, 'm1', @sec_m1, 'm2', @sec_m2, 'm3', @sec_m3, ...
             'svm', @sec_svm, 'pipeline', @sec_pipeline, 'sweep', @sec_sweep, 'diagram', @sec_diagram, 'real', @sec_real);
for k = 1:numel(sections)
    name = sections{k};
    fprintf('=== section %s ===\n', name);
    t0 = tic;
    try
        S = sec.(name)(ctx);
        S.generated = datestr(now, 'yyyy-mm-dd HH:MM');
        S.matlab = version;
        writeJson(fullfile(ctx.dataDir, [name '.json']), S);
    catch ME
        fprintf(2, 'SECTION %s FAILED:\n%s\n', name, getReport(ME));
    end
    fprintf('    %.1f s\n', toc(t0));
end
end

% =============================================================================
%  helpers
% =============================================================================
function f = newFig(w, h)
f = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 w h]);
lightFig(f);
end

function lightFig(f)
try, f.Theme = 'light'; catch, end                         %#ok<NOCOM> older releases have no Theme
end

function saveFig(f, ctx, name)
% Export at 150 dpi, trim the white margins and write to report/figures.
tmp = [tempname '.png'];
exportgraphics(f, tmp, 'Resolution', 150, 'BackgroundColor', 'white');
close(f);
cropFile(tmp, fullfile(ctx.figDir, name));
delete(tmp);
end

function cropFile(inFile, outFile)
A = imread(inFile);
m = any(A < 245, 3);
r = find(any(m, 2));  c = find(any(m, 1));
pad = 12;
A = A(max(1, r(1)-pad):min(size(A,1), r(end)+pad), max(1, c(1)-pad):min(size(A,2), c(end)+pad), :);
imwrite(A, outFile);
end

function writeJson(file, S)
txt = jsonencode(S, 'PrettyPrint', true);
fid = fopen(file, 'w');
fwrite(fid, txt, 'char');
fclose(fid);
end

function p = psnrOf(A, B)
[~, p] = imageMetrics(A, B);
end

function d = dice(A, B)
d = 2 * nnz(A & B) / max(nnz(A) + nnz(B), 1);
end

function e = entropyOf(X)
p = accumarray(min(floor(X(:) * 256), 255) + 1, 1, [256 1]) / numel(X);
p = p(p > 0);
e = -sum(p .* log2(p));
end

% =============================================================================
%  section: code statistics and function list
% =============================================================================
function S = sec_code(ctx)
mods = {'common', 'module1_enhancement', 'module2_segmentation', 'module3_geometry', 'svm', 'lpr'};
S.modules = struct();
total = 0;  totalComments = 0;  totalFiles = 0;
for k = 1:numel(mods)
    files = dir(fullfile(ctx.root, 'toolbox', mods{k}, '*.m'));
    items = struct('file', {}, 'signature', {}, 'description', {}, 'lines', {}, 'commentLines', {});
    for q = 1:numel(files)
        items(end+1) = describeFile(fullfile(files(q).folder, files(q).name)); %#ok<AGROW>
    end
    S.modules.(mods{k}) = items;
    total = total + sum([items.lines]);  totalComments = totalComments + sum([items.commentLines]);
    totalFiles = totalFiles + numel(items);
end
extra = {fullfile('toolbox', 'toolboxOperations.m'), 'LPR_Toolbox.m', 'train_lpr_model.m', 'demo_lpr.m', ...
         'demo_modules.m', 'run_tests.m', 'setup_toolbox.m'};
items = struct('file', {}, 'signature', {}, 'description', {}, 'lines', {}, 'commentLines', {});
for q = 1:numel(extra)
    items(end+1) = describeFile(fullfile(ctx.root, extra{q})); %#ok<AGROW>
end
S.modules.app = items;
total = total + sum([items.lines]);  totalComments = totalComments + sum([items.commentLines]);
totalFiles = totalFiles + numel(items);
S.totalLines = total;  S.totalCommentLines = totalComments;  S.totalFiles = totalFiles;

% names of the self-checks in run_tests.m
txt = fileread(fullfile(ctx.root, 'run_tests.m'));
tok = regexp(txt, "check\('([^']+)'", 'tokens');
S.testNames = cellfun(@(t) t{1}, tok, 'UniformOutput', false);
S.nTests = numel(S.testNames);

% operations offered by the GUI
ops = toolboxOperations();
S.ops = struct('module', {}, 'name', {}, 'params', {});
for k = 1:numel(ops)
    if isempty(ops(k).params), labels = {}; else, labels = {ops(k).params.label}; end
    S.ops(k) = struct('module', ops(k).module, 'name', strrep(ops(k).name, '&&', '&'), 'params', strjoin(labels, '; '));
end
end

function S = sec_diagram(ctx)
drawPipelineDiagram(ctx);
S = struct('done', true);
end

function it = describeFile(f)
txt = fileread(f);
lines = splitlines(txt);
[~, name, ext] = fileparts(f);
it.file = [name ext];
first = strtrim(lines{1});
if startsWith(first, 'function')
    it.signature = strtrim(regexprep(first, '^function\s+', ''));
else
    it.signature = [name ' (script)'];
end
h1 = '';
for k = 1:numel(lines)
    s = strtrim(lines{k});
    if startsWith(s, '%')
        h1 = strtrim(s(2:end));
        break
    end
end
tok = regexp(h1, '^\S+\s+(.*)$', 'tokens', 'once');
if isempty(tok), it.description = h1; else, it.description = strtrim(tok{1}); end
it.lines = numel(lines);
it.commentLines = nnz(startsWith(strtrim(lines), '%'));
end

% =============================================================================
%  section: Module 1
% =============================================================================
function S = sec_m1(ctx)
I = ctx.I;  G = ctx.G;
rows = 190:350;  cols = 200:460;                             % car grille + plate, for close-ups

fig = compareEnhancement(I);  lightFig(fig);  fig.Position = [0 0 1300 780];
saveFig(fig, ctx, 'm1_enhancement.png');

% ---- histogram processing ---------------------------------------------------
Gl = 0.30 + 0.25 * (G - min(G(:))) / (max(G(:)) - min(G(:)));      % low-contrast copy
Ge = histEqualize(Gl);
Gm = histMatch(Gl, G);
fig = newFig(1200, 560);
items = {Gl, 'Low-contrast input'; Ge, 'Histogram equalisation'; Gm, 'Matched to reference'; G, 'Reference image'};
for k = 1:4
    showImage(subplot(2, 4, k), items{k,1}, items{k,2});
    ax = subplot(2, 4, 4 + k);
    h = accumarray(min(floor(items{k,1}(:) * 64), 63) + 1, 1, [64 1]) / numel(G);
    bar(ax, ((1:64) - 0.5) / 64, h, 1, 'FaceColor', [0.25 0.4 0.8], 'EdgeColor', 'none');
    xlim(ax, [0 1]);  set(ax, 'FontSize', 8);  xlabel(ax, 'gray level');  ylabel(ax, 'fraction of pixels');
end
saveFig(fig, ctx, 'm1_histograms.png');
S.hist.stdInput = std(Gl(:));   S.hist.stdEqualised = std(Ge(:));   S.hist.stdMatched = std(Gm(:));
S.hist.entropyInput = entropyOf(Gl);  S.hist.entropyEqualised = entropyOf(Ge);
S.hist.meanInput = mean(Gl(:));  S.hist.meanMatched = mean(Gm(:));  S.hist.meanReference = mean(G(:));
S.hist.stdReference = std(G(:));

% ---- noise reduction -----------------------------------------------------------
rng(11);  Gg = addNoise(G, 'gaussian', 0.08);
rng(12);  Gs = addNoise(G, 'saltpepper', 0.10);
gm = smoothFilter(Gg, 'mean', 3);       gg = smoothFilter(Gg, 'gaussian', 5, 1);
gmed = smoothFilter(Gg, 'median', 3);   gf = freqFilter(Gg, 'lowpass', 0.25, 'butterworth', 2);
sm = smoothFilter(Gs, 'mean', 3);       sg = smoothFilter(Gs, 'gaussian', 5, 1);
smed = smoothFilter(Gs, 'median', 3);   smed5 = smoothFilter(Gs, 'median', 5);
S.noise.gaussian = struct('noisy', psnrOf(G, Gg), 'mean3', psnrOf(G, gm), 'gauss5', psnrOf(G, gg), ...
                          'median3', psnrOf(G, gmed), 'fftLowpass', psnrOf(G, gf));
S.noise.saltpepper = struct('noisy', psnrOf(G, Gs), 'mean3', psnrOf(G, sm), 'gauss5', psnrOf(G, sg), ...
                            'median3', psnrOf(G, smed), 'median5', psnrOf(G, smed5));
fig = newFig(1300, 440);
T = {Gg,   'Gaussian noise (0.08)';  gm,  'Mean 3x3';      gg,  'Gaussian 5x5';  gmed,  'Median 3x3';  gf,  'FFT low-pass';
     Gs,   'Salt & pepper (10 %)';   sm,  'Mean 3x3';      sg,  'Gaussian 5x5';  smed,  'Median 3x3';  smed5, 'Median 5x5'};
P = [S.noise.gaussian.noisy S.noise.gaussian.mean3 S.noise.gaussian.gauss5 S.noise.gaussian.median3 S.noise.gaussian.fftLowpass ...
     S.noise.saltpepper.noisy S.noise.saltpepper.mean3 S.noise.saltpepper.gauss5 S.noise.saltpepper.median3 S.noise.saltpepper.median5];
for k = 1:10
    ax = subplot(2, 5, k);
    showImage(ax, T{k,1}(rows, cols), sprintf('%s\nPSNR %.1f dB', T{k,2}, P(k)));
end
saveFig(fig, ctx, 'm1_noise.png');

% ---- sharpening -----------------------------------------------------------------
lapk = [0 1 0; 1 -4 1; 0 1 0];
edgeEnergy = @(X) std(reshape(spatialFilter(X, lapk), [], 1));
S.sharpen.original = edgeEnergy(G);
S.sharpen.laplacian = edgeEnergy(sharpenFilter(G, 'laplacian', 1));
S.sharpen.highpass  = edgeEnergy(sharpenFilter(G, 'highpass', 1));
S.sharpen.unsharp   = edgeEnergy(sharpenFilter(G, 'unsharp', 1.5));

% ---- frequency domain ------------------------------------------------------------
[Jid, Hid, Sp] = freqFilter(G, 'lowpass', 0.10, 'ideal');
[Jbw, Hbw] = freqFilter(G, 'lowpass', 0.10, 'butterworth', 2);
[Jg,  Hg ] = freqFilter(G, 'lowpass', 0.10, 'gaussian');
Jhp = freqFilter(G, 'highpass', 0.05, 'butterworth', 2);
Jbp = freqFilter(G, 'bandpass', [0.05 0.25], 'gaussian');
fig = newFig(1300, 470);
showImage(subplot(2, 5, 1), G, 'Input');
showImage(subplot(2, 5, 2), Sp, 'Log-magnitude spectrum');
showImage(subplot(2, 5, 3), Hid, 'H: ideal low-pass');
showImage(subplot(2, 5, 4), Hbw, 'H: Butterworth low-pass');
showImage(subplot(2, 5, 5), Hg, 'H: Gaussian low-pass');
r2 = 200:340;  c2 = 180:480;
showImage(subplot(2, 5, 6), Jid(r2, c2), 'Ideal LP (ringing)');
showImage(subplot(2, 5, 7), Jbw(r2, c2), 'Butterworth LP');
showImage(subplot(2, 5, 8), Jg(r2, c2),  'Gaussian LP');
showImage(subplot(2, 5, 9), Jhp(r2, c2), 'Butterworth high-pass');
showImage(subplot(2, 5, 10), Jbp(r2, c2), 'Gaussian band-pass');
saveFig(fig, ctx, 'm1_frequency.png');
S.freq.lowpassPsnr = struct('ideal', psnrOf(G, Jid), 'butterworth', psnrOf(G, Jbw), 'gaussian', psnrOf(G, Jg));
cuts = [0.15 0.25 0.35];
shapes = {'ideal', 'butterworth', 'gaussian'};
S.freq.cutoffs = cuts;
for q = 1:3
    v = zeros(1, numel(cuts));
    for k = 1:numel(cuts)
        v(k) = psnrOf(G, freqFilter(Gg, 'lowpass', cuts(k), shapes{q}, 2));
    end
    S.freq.denoise.(shapes{q}) = v;
end
S.freq.noisyPsnr = psnrOf(G, Gg);
end

% =============================================================================
%  section: Module 2
% =============================================================================
function S = sec_m2(ctx)
I = ctx.I;  G = ctx.G;  gt = ctx.gt;

fig = compareEdgeDetectors(I);  lightFig(fig);  fig.Position = [0 0 1300 700];
saveFig(fig, ctx, 'm2_edges.png');
E = edgeDetect(G, 'canny');
S.timing.cannyMs = timeit(@() edgeDetect(G, 'canny')) * 1000;
S.timing.labelMs = timeit(@() labelComponents(E, 8)) * 1000;
S.timing.edgePixels = nnz(E);

% ---- edge detector evaluation on shapes with known edges ------------------------
[x, y] = meshgrid(1:240, 1:240);
mask = (x >= 30 & x <= 110 & y >= 40 & y <= 120) | ((x-170).^2 + (y-80).^2 <= 40^2) | (((x-120)/55).^2 + ((y-180)/28).^2 <= 1);
img0 = spatialFilter(0.25 + 0.55 * double(mask), gaussianKernel(5, 0.8));
bnd = mask & ~morphOp(mask, 'erode', makeSE('cross', 3));
sigmas = [0.02 0.08];
methods = {'sobel', 'prewitt', 'canny'};
fig = newFig(1300, 600);
S.edge.sigmas = sigmas;
for s = 1:numel(sigmas)
    rng(30 + s);
    noisy = min(max(img0 + sigmas(s) * randn(size(img0)), 0), 1);
    showImage(subplot(2, 4, 4*(s-1) + 1), noisy, sprintf('Test image, noise %.2f', sigmas(s)));
    for m = 1:3
        Em = edgeDetect(noisy, methods{m});
        [P, R, F] = edgeScore(Em, bnd);
        S.edge.(methods{m})(s) = struct('precision', P, 'recall', R, 'f1', F);
        showImage(subplot(2, 4, 4*(s-1) + 1 + m), Em, sprintf('%s  F1 = %.2f', methods{m}, F));
    end
end
saveFig(fig, ctx, 'm2_edge_eval.png');
for m = 1:3, S.edge.(methods{m}) = S.edge.(methods{m})(:).'; end

% ---- segmentation: global vs adaptive threshold under uneven light --------------
fig = compareSegmentation(I);  lightFig(fig);  fig.Position = [0 0 1300 700];
saveFig(fig, ctx, 'm2_segmentation.png');
[x, y] = meshgrid(1:320, 1:240);
obj = false(240, 320);
cen = [40 50; 95 160; 150 60; 200 190; 260 70; 280 180; 60 200; 130 120];
for k = 1:size(cen, 1)
    if mod(k, 2), obj = obj | ((x - cen(k,1)).^2 + (y - cen(k,2)).^2 <= 15^2);
    else,         obj = obj | (abs(x - cen(k,1)) <= 16 & abs(y - cen(k,2)) <= 12); end
end
rng(5);
shade = repmat(linspace(0.30, 1.20, 320), 240, 1);             % strong lighting gradient (4x)
img = min(max((0.18 + 0.45 * double(obj)) .* shade + 0.03 * randn(240, 320), 0), 1);
sm = smoothFilter(img, 'gaussian', 5, 1);                      % the same pre-processing for every method
[tOtsu, Bo] = otsuThreshold(sm);
Ba = adaptiveThreshold(sm, 41, 0.03, 'bright');
seed = [cen(2,2) cen(2,1)];                                    % [row col] inside the second object
Br = regionGrow(sm, seed, 0.10);
oneObj = ((x - cen(2,1)).^2 + (y - cen(2,2)).^2 <= 15^2) | (abs(x - cen(2,1)) <= 16 & abs(y - cen(2,2)) <= 12);
S.seg.otsuDice = dice(Bo, obj);  S.seg.adaptiveDice = dice(Ba, obj);
S.seg.regionDice = dice(Br, oneObj & obj);  S.seg.otsuLevel = tOtsu;
fig = newFig(1300, 560);
showImage(subplot(2, 3, 1), img, 'Objects under a lighting gradient');
showImage(subplot(2, 3, 2), obj, 'Ground truth');
showImage(subplot(2, 3, 3), Bo, sprintf('Otsu (t = %.2f)  Dice %.2f', tOtsu, S.seg.otsuDice));
showImage(subplot(2, 3, 4), Ba, sprintf('Adaptive 41x41  Dice %.2f', S.seg.adaptiveDice));
ax = subplot(2, 3, 5);
showImage(ax, Br, sprintf('Region growing from one seed  Dice %.2f', S.seg.regionDice));
saveFig(fig, ctx, 'm2_seg_eval.png');

% ---- morphology on the license plate text ---------------------------------------
r = gt.bbox(2):gt.bbox(2)+gt.bbox(4)-1;  c = gt.bbox(1):gt.bbox(1)+gt.bbox(3)-1;
[~, Bp] = otsuThreshold(G(r, c));
ink = ~Bp;
rng(21);
noisy = xor(ink, rand(size(ink)) < 0.02);
se = makeSE('square', 3);
opened = morphOp(noisy, 'open', se);
closed = morphOp(noisy, 'close', se);
both = morphOp(opened, 'close', se);
grad = morphOp(ink, 'gradient', se);
dil = morphOp(ink, 'dilate', se);
ero = morphOp(ink, 'erode', se);
fig = newFig(1000, 540);
M = {ink, 'Clean binary text'; noisy, 'With 2 % salt-and-pepper noise'; opened, 'Opening 3x3 (removes specks)'; closed, 'Closing 3x3 (fills holes)'; ...
     both, 'Opening then closing'; grad, 'Morphological gradient'; dil, 'Dilation 3x3'; ero, 'Erosion 3x3'};
for k = 1:8
    showImage(subplot(4, 2, k), M{k,1}, M{k,2});
end
saveFig(fig, ctx, 'm2_morphology.png');
cnt = @(B) max(max(labelComponents(B, 8)));
S.morph.components = struct('clean', cnt(ink), 'noisy', cnt(noisy), 'opened', cnt(opened), 'openedClosed', cnt(both));

% ---- region growing sensitivity on the plate background -------------------------
Gp = spatialFilter(G, gaussianKernel(7, 1.5));
sub = Gp(r, c);
[~, k] = max(sub(:));
[sr, sc] = ind2sub(size(sub), k);
seed = [r(1) + sr - 1, c(1) + sc - 1];
tols = [0.03 0.08 0.20];
fig = newFig(1100, 800);
ax = subplot(2, 2, 1);
showImage(ax, I, 'Input and seed');
hold(ax, 'on');  plot(ax, seed(2), seed(1), 'r+', 'MarkerSize', 12, 'LineWidth', 2);
for k = 1:3
    [B, nIt] = regionGrow(G, seed, tols(k));
    V = I;
    V(:,:,1) = max(V(:,:,1), 0.9 * double(B));
    V(:,:,2) = V(:,:,2) .* (1 - 0.7 * double(B));
    V(:,:,3) = V(:,:,3) .* (1 - 0.7 * double(B));
    showImage(subplot(2, 2, 1 + k), V, sprintf('Tolerance %.2f: %.1f %% of image', tols(k), 100 * mean(B(:))));
    S.region.fraction(k) = mean(B(:));  S.region.iterations(k) = nIt;
end
S.region.tolerances = tols;
saveFig(fig, ctx, 'm2_region_grow.png');
end

function [P, R, F] = edgeScore(E, bnd)
tol = makeSE('disk', 2);
nearGT = morphOp(bnd, 'dilate', tol);
nearE  = morphOp(E, 'dilate', tol);
P = nnz(E & nearGT) / max(nnz(E), 1);
R = nnz(bnd & nearE) / nnz(bnd);
F = 2 * P * R / max(P + R, eps);
end

% =============================================================================
%  section: Module 3
% =============================================================================
function S = sec_m3(ctx)
I = ctx.I;  G = ctx.G;  gt = ctx.gt;
cr = 60:420;  cc = 80:560;                                    % central region, avoids rotation corners

fig = compareGeometry(I);  lightFig(fig);  fig.Position = [0 0 1300 780];
saveFig(fig, ctx, 'm3_geometry.png');

% ---- interpolation ----------------------------------------------------------------
methods = {'nearest', 'bilinear', 'bicubic'};
for k = 1:3
    m = methods{k};
    up = imResize(imResize(G, 0.5, m), size(G), m);
    back = geometricTransforms(geometricTransforms(G, 'rotate', 10, m), 'rotate', -10, m);
    S.interp.resizeRoundTrip.(m) = psnrOf(G, up);
    S.interp.rotateRoundTrip.(m) = psnrOf(G(cr, cc), back(cr, cc));
    S.interp.enlargeMs.(m) = timeit(@() imResize(G, 2, m)) * 1000;
end
r0 = gt.bbox(2) + 6;  c0 = gt.bbox(1) + 8;
patch = G(r0:r0+19, c0:c0+49);
fig = newFig(900, 520);
showImage(subplot(2, 2, 1), patch, 'Source patch (20 x 50 pixels)');
for k = 1:3
    showImage(subplot(2, 2, 1 + k), imResize(patch, 8, methods{k}), sprintf('%s, enlarged 8x', methods{k}));
end
saveFig(fig, ctx, 'm3_interp.png');

% ---- forward vs reverse mapping ---------------------------------------------------
T = diag([1.6 1.6 1]);
one = ones(240, 320);
region = false(size(one));  region(3:end, 3:end) = true;
Jn = warpImage(one, T, size(one), 'nearest', 'forward', 0);
Jb = warpImage(one, T, size(one), 'bilinear', 'forward', 0);
Jr = warpImage(one, T, size(one), 'bilinear', 'reverse', 0);
S.mapping.forwardNearestHolesPct = 100 * mean(Jn(region) == 0);
S.mapping.forwardBilinearHolesPct = 100 * mean(Jb(region) == 0);
S.mapping.reverseHolesPct = 100 * mean(Jr(region) == 0);

% ---- radial distortion --------------------------------------------------------------
lines = false(480, 640);  lines(20:40:end, :) = true;  lines(:, 20:40:end) = true;
grid = 1 - double(morphOp(lines, 'dilate', makeSE('square', 3)));
cg = 96:384;  cgc = 128:512;
fig = newFig(1200, 640);
ks = [-0.15 0.3];
names = {'barrel', 'pincushion'};
for q = 1:2
    d = radialDistortion(grid, ks(q), 0, 'apply');
    c = radialDistortion(d, ks(q), 0, 'correct');
    showImage(subplot(2, 3, 3*(q-1) + 1), grid, 'Original grid');
    showImage(subplot(2, 3, 3*(q-1) + 2), d, sprintf('%s distortion, k1 = %.2f', names{q}, ks(q)));
    showImage(subplot(2, 3, 3*(q-1) + 3), c, 'After correction');
    S.radial.(names{q}) = struct('k1', ks(q), 'psnrDistorted', psnrOf(grid(cg, cgc), d(cg, cgc)), ...
                                 'psnrCorrected', psnrOf(grid(cg, cgc), c(cg, cgc)));
end
dS = radialDistortion(G, -0.25, 0, 'apply');  cS = radialDistortion(dS, -0.25, 0, 'correct');
S.radial.sceneRoundTripPsnr = psnrOf(G(cr, cc), cS(cr, cc));
saveFig(fig, ctx, 'm3_radial.png');

% ---- registration -------------------------------------------------------------------
rng(3);
[mov1, T1] = geometricTransforms(G, 'rotate', 8, 'bilinear');
[mov, T2]  = geometricTransforms(mov1, 'translate', 12, -7, 'bilinear');
Ttrue = T2 * T1;                                               % fixed -> moving
tic;  [Tf, reg, info] = registerImages(G, mov, 'features');  S.reg.featuresSeconds = toc;
comp = Tf * Ttrue;                                             % should be the identity
[px, py] = meshgrid(80:100:560, 60:100:420);
pts = [px(:).'; py(:).'; ones(1, numel(px))];
q = comp * pts;
S.reg.features = struct('matches', info.matches, 'inliers', info.inliers, ...
    'rotationErrorDeg', abs(atan2(comp(2,1), comp(1,1)) * 180 / pi), ...
    'meanPointErrorPx', mean(hypot(q(1,:) - pts(1,:), q(2,:) - pts(2,:))), ...
    'psnrBefore', psnrOf(G(cr, cc), mov(cr, cc)), 'psnrAfter', psnrOf(G(cr, cc), reg(cr, cc)));
mov2 = geometricTransforms(G, 'translate', 9, -5, 'bilinear');
[~, ~, ip] = registerImages(G, mov2, 'phase');
S.reg.phase = struct('shiftFound', ip.shift, 'shiftExpected', [-9 5]);
tile = 40;
cb = mod(floor((0:size(G,1)-1).' / tile) + floor((0:size(G,2)-1) / tile), 2) == 1;
mix = G;  mix(cb) = reg(cb);
fig = newFig(1300, 700);
showImage(subplot(2, 3, 1), G, 'Fixed image');
showImage(subplot(2, 3, 2), mov, 'Moving: rotated 8 deg, shifted (12,-7)');
showImage(subplot(2, 3, 3), reg, 'Registered moving image');
showImage(subplot(2, 3, 4), min(3 * abs(G - mov), 1), sprintf('|difference| before (PSNR %.1f dB)', S.reg.features.psnrBefore));
showImage(subplot(2, 3, 5), min(3 * abs(G - reg), 1), sprintf('|difference| after (PSNR %.1f dB)', S.reg.features.psnrAfter));
showImage(subplot(2, 3, 6), mix, 'Checkerboard: fixed / registered');
saveFig(fig, ctx, 'm3_registration.png');
end

% =============================================================================
%  section: SVM
% =============================================================================
function S = sec_svm(ctx)
tpl = ctx.tpl;

% ---- toy problem: why a kernel is needed ------------------------------------------
rng(2);
n = 150;  t = 2*pi*rand(2*n, 1);  r = [1 + 0.15*randn(n,1); 2.2 + 0.15*randn(n,1)];
X = [r.*cos(t), r.*sin(t)];  y = [ones(n,1); -ones(n,1)];
idx = randperm(2*n);  tr = idx(1:200);  te = idx(201:end);
kps = {struct('type', 'linear', 'gamma', 1), struct('type', 'rbf', 'gamma', 1)};
ttl = {'Linear kernel', 'RBF kernel (gamma = 1)'};
[gx, gy] = meshgrid(linspace(-3.4, 3.4, 220));
fig = newFig(1100, 520);
for k = 1:2
    m = svmTrainBinary(X(tr,:), y(tr), 10, kps{k});
    Z = reshape(kernelMatrix([gx(:) gy(:)], X(tr(m.idx),:), kps{k}) * m.coef + m.b, size(gx));
    acc = mean(sign(kernelMatrix(X(te,:), X(tr(m.idx),:), kps{k}) * m.coef + m.b) == y(te));
    ax = subplot(1, 2, k);
    imagesc(ax, gx(1,:), gy(:,1), double(Z > 0));  set(ax, 'YDir', 'normal');
    colormap(ax, [0.98 0.86 0.78; 0.80 0.88 0.97]);  hold(ax, 'on');
    plot(ax, X(tr(y(tr) == 1), 1),  X(tr(y(tr) == 1), 2),  'o', 'MarkerSize', 4, 'MarkerFaceColor', [0.85 0.4 0.1], 'MarkerEdgeColor', 'none');
    plot(ax, X(tr(y(tr) == -1), 1), X(tr(y(tr) == -1), 2), 'o', 'MarkerSize', 4, 'MarkerFaceColor', [0.15 0.4 0.8], 'MarkerEdgeColor', 'none');
    plot(ax, X(tr(m.idx), 1), X(tr(m.idx), 2), 'ko', 'MarkerSize', 8);
    contour(ax, gx, gy, Z, [0 0], 'k', 'LineWidth', 1.5);
    axis(ax, 'image');  set(ax, 'XTick', [], 'YTick', []);
    title(ax, sprintf('%s: accuracy %.0f %%, %d support vectors', ttl{k}, 100 * acc, numel(m.idx)), 'FontWeight', 'normal', 'Color', [0.1 0.1 0.1]);
    S.toy.(kps{k}.type) = struct('accuracy', acc, 'supportVectors', numel(m.idx));
end
saveFig(fig, ctx, 'svm_toy.png');

% ---- character samples -----------------------------------------------------------------
trainFonts = find(~tpl.isTest);  testFonts = find(tpl.isTest);
[~, ~, imgs] = generateCharDataset(tpl, trainFonts, 3, 1);
M = ones(3*34, 36*34);
for k = 1:108
    row = floor((k-1) / 36);  col = mod(k-1, 36);
    M(row*34 + (2:33), col*34 + (2:33)) = 1 - double(imgs(:,:,k)) / 255;
end
imwrite(imresizeNearest(M, 2), fullfile(ctx.figDir, 'char_samples.png'));

% ---- datasets ----------------------------------------------------------------------------
fprintf('    generating datasets ...\n');
[Xtr, ytr] = generateCharDataset(tpl, trainFonts, 250, 7);
[Xte, yte] = generateCharDataset(tpl, testFonts, 40, 207);
[Xse, yse] = generateCharDataset(tpl, trainFonts, 20, 107);
S.data = struct('trainSamples', size(Xtr, 1), 'unseenFontSamples', size(Xte, 1), 'seenFontSamples', size(Xse, 1), ...
                'features', size(Xtr, 2), 'classes', 36, 'trainFonts', numel(trainFonts), 'testFonts', numel(testFonts));

% ---- learning curve ----------------------------------------------------------------------
ns = [10 25 50 100 250];
for k = 1:numel(ns)
    rowsN = 1:36*ns(k);
    tic;  m = svmTrain(Xtr(rowsN,:), ytr(rowsN), 'C', 10);  tt = toc;
    S.curve.n(k) = ns(k);
    S.curve.unseen(k) = mean(svmPredict(m, Xte) == yte);
    S.curve.seen(k) = mean(svmPredict(m, Xse) == yse);
    S.curve.trainSeconds(k) = tt;
    S.curve.supportVectors(k) = size(m.SV, 1);
    fprintf('    n=%d: unseen %.2f %%\n', ns(k), 100 * S.curve.unseen(k));
end

% ---- kernels ---------------------------------------------------------------------------------
kn = {'linear', 'rbf', 'poly'};
for k = 1:3
    tic;  m = svmTrain(Xtr, ytr, 'C', 10, 'Kernel', kn{k});  tt = toc;
    pr = svmPredict(m, Xte);
    S.kernel.(kn{k}) = struct('unseenAccuracy', mean(pr == yte), 'seenAccuracy', mean(svmPredict(m, Xse) == yse), ...
                              'trainSeconds', tt, 'supportVectors', size(m.SV, 1));
    if strcmp(kn{k}, 'rbf'), mRbf = m;  prRbf = pr; end
    fprintf('    kernel %s: %.2f %%\n', kn{k}, 100 * S.kernel.(kn{k}).unseenAccuracy);
end
S.model.features = size(Xtr, 2);  S.model.binaryMachines = numel(mRbf.machines);
S.model.sharedSupportVectors = size(mRbf.SV, 1);  S.model.gamma = mRbf.kernel.gamma;

% ---- C / gamma grid -------------------------------------------------------------------------
Cs = [1 10 100];  gm = [0.5 1 2];
g0 = 1 / (size(Xtr, 2) * var(Xtr(:)));
A = zeros(numel(Cs), numel(gm));
for i = 1:numel(Cs)
    for j = 1:numel(gm)
        m = svmTrain(Xtr, ytr, 'C', Cs(i), 'Gamma', g0 * gm(j));
        A(i, j) = mean(svmPredict(m, Xte) == yte);
    end
end
S.grid = struct('C', Cs, 'gammaFactor', gm, 'gammaScale', g0, 'accuracy', A);

fig = newFig(1100, 440);
ax = subplot(1, 2, 1);
semilogx(ax, ns, 100 * S.curve.unseen, 'o-', 'LineWidth', 1.6, 'Color', [0.85 0.35 0.1], 'MarkerFaceColor', [0.85 0.35 0.1]);
hold(ax, 'on');
semilogx(ax, ns, 100 * S.curve.seen, 's-', 'LineWidth', 1.6, 'Color', [0.2 0.4 0.8], 'MarkerFaceColor', [0.2 0.4 0.8]);
grid(ax, 'on');  xlabel(ax, 'training images per character');  ylabel(ax, 'character accuracy (%)');
legend(ax, {'unseen fonts', 'fonts seen in training'}, 'Location', 'southeast');
title(ax, 'Learning curve', 'FontWeight', 'normal');
ax = subplot(1, 2, 2);
imagesc(ax, 100 * A);  colormap(ax, flipud(gray(256)) * 0.45 + 0.55);        % light colours: dark text stays readable
set(ax, 'XTick', 1:3, 'XTickLabel', arrayfun(@(v) sprintf('%.1f x', v), gm, 'UniformOutput', false), ...
        'YTick', 1:3, 'YTickLabel', arrayfun(@(v) sprintf('C = %g', v), Cs, 'UniformOutput', false));
xlabel(ax, 'gamma (multiple of 1/(d*var))');
for i = 1:numel(Cs)
    for j = 1:numel(gm)
        text(ax, j, i, sprintf('%.1f', 100 * A(i,j)), 'HorizontalAlignment', 'center', 'Color', [0.05 0.05 0.05], 'FontWeight', 'bold');
    end
end
title(ax, 'Accuracy on unseen fonts (%)', 'FontWeight', 'normal');  colorbar(ax);
saveFig(fig, ctx, 'svm_curves.png');

% ---- confusion matrix on unseen fonts -------------------------------------------------------
Cm = accumarray([yte, prRbf], 1, [36 36]);
rowN = Cm ./ max(sum(Cm, 2), 1);
fig = newFig(760, 700);
ax = axes(fig);
imagesc(ax, rowN);  colormap(ax, flipud(gray(256)));  colorbar(ax);
chars = num2cell(tpl.chars);
set(ax, 'XTick', 1:36, 'XTickLabel', chars, 'YTick', 1:36, 'YTickLabel', chars, 'FontSize', 8, 'TickLength', [0 0]);
xlabel(ax, 'predicted character');  ylabel(ax, 'true character');
title(ax, 'Confusion matrix, 4 unseen fonts (row-normalised)', 'FontWeight', 'normal');
axis(ax, 'image');
saveFig(fig, ctx, 'svm_confusion.png');
off = Cm;  off(1:37:end) = 0;
[~, order] = sort(off(:), 'descend');
for k = 1:10
    [a, b] = ind2sub([36 36], order(k));
    S.topConfusions(k) = struct('truth', tpl.chars(a), 'read', tpl.chars(b), 'count', off(a, b), 'of', sum(Cm(a, :)));
end
S.confusionOverallAccuracy = sum(diag(Cm)) / sum(Cm(:));
end

function B = imresizeNearest(A, f)
B = kron(A, ones(f));
end

% =============================================================================
%  section: pipeline, evaluation and error analysis
% =============================================================================
function S = sec_pipeline(ctx)
tpl = ctx.tpl;
L = load(fullfile(ctx.root, 'models', 'lpr_svm_model_holdout.mat'));  model = L.model;
S.model = struct('supportVectors', size(model.svm.SV, 1), 'trainSeconds', model.report.trainTime, ...
                 'unseenFontAccuracy', model.report.unseenFontAcc, 'trainAccuracy', model.report.trainAcc, ...
                 'nTrain', model.report.nTrain);

% ---- block diagram ---------------------------------------------------------------------------
drawPipelineDiagram(ctx);

% ---- one example through every stage -------------------------------------------------------
rng(8);
[img, gt] = makeScene(tpl, find(tpl.isTest), 'Hard', 0.4);
res = recognizePlate(img, model);
fig = showPipeline(img, res, 'off');  lightFig(fig);  fig.Position = [0 0 1300 820];
saveFig(fig, ctx, 'pipeline_stages.png');
S.example = struct('truth', gt.text, 'read', res.text, 'font', gt.font);

% ---- evaluation at three difficulty levels --------------------------------------------------
levels = [0.2 0.5 0.8];
for k = 1:numel(levels)
    tmp = [tempname '.png'];
    R = evaluateLPR(model, 'N', 100, 'Hard', levels(k), 'Seed', 123, 'Figure', tmp);
    R = rmfield(R, {'truth', 'predNoFormat', 'predWithFormat'});
    S.eval(k) = R;
    if levels(k) == 0.5, cropFile(tmp, fullfile(ctx.figDir, 'eval_examples.png')); end
    delete(tmp);
end

% ---- error analysis (new scenes, difficulty 0.5, no layout hint) ----------------------------
rng(321);
N = 150;
kinds = {'correct', 'lookalike', 'otherSubstitution', 'wrongCount', 'wrongRegion', 'notFound'};
counts = zeros(1, numel(kinds));
fails = {};
fontNames = {};  fontOk = [];
tD = zeros(N, 1);  tS = tD;  tC = tD;
look = {'O0', 'I1', 'B8', 'S5', 'Z2', 'D0', 'Q0', 'G6', 'QO', 'DO', 'UV', 'IL', 'G0', 'CG'};
for k = 1:N
    [img, gt] = makeScene(tpl, find(tpl.isTest), 'Hard', 0.5);
    t0 = tic;  [bbox, plate] = detectPlate(img);  tD(k) = toc(t0);
    res = struct('found', false, 'text', '');
    if ~isempty(bbox)
        t0 = tic;  [chars, ~, ~] = segmentChars(plate);  tS(k) = toc(t0);
        if ~isempty(chars)
            t0 = tic;
            Xc = zeros(numel(chars), 324);
            for q = 1:numel(chars), Xc(q, :) = hogFeatures(chars{q}); end
            pred = svmPredict(model.svm, Xc);
            tC(k) = toc(t0);
            res.found = true;  res.text = model.charset(pred(:).');
        end
    end
    if isempty(bbox),                                  kind = 'notFound';
    elseif bboxIou(bbox, gt.bbox) <= 0.5,              kind = 'wrongRegion';
    elseif ~res.found || numel(res.text) ~= numel(gt.text), kind = 'wrongCount';
    elseif strcmp(res.text, gt.text),                  kind = 'correct';
    else
        d = find(res.text ~= gt.text);
        pairs = arrayfun(@(i) [gt.text(i) res.text(i)], d, 'UniformOutput', false);
        isLook = cellfun(@(p) any(strcmp(p, look) | strcmp(fliplr(p), look)), pairs);
        if all(isLook), kind = 'lookalike'; else, kind = 'otherSubstitution'; end
    end
    counts(strcmp(kinds, kind)) = counts(strcmp(kinds, kind)) + 1;
    fontNames{end+1} = gt.font; %#ok<AGROW>
    fontOk(end+1) = strcmp(kind, 'correct'); %#ok<AGROW>
    if ~strcmp(kind, 'correct') && ~isempty(plate) && numel(fails) < 8
        fails{end+1} = {plate, gt.text, res.text, kind}; %#ok<AGROW>
    end
end
S.errors = cell2struct(num2cell(counts), kinds, 2);
S.errorsN = N;
u = unique(fontNames);
for k = 1:numel(u)
    sel = strcmp(fontNames, u{k});
    S.perFont(k) = struct('font', u{k}, 'n', nnz(sel), 'exactNoLayout', mean(fontOk(sel)));
end
S.timing = struct('detectMs', 1000 * mean(tD), 'segmentMs', 1000 * mean(tS), 'classifyMs', 1000 * mean(tC));
if ~isempty(fails)
    fig = newFig(1200, 140 * ceil(numel(fails) / 2) + 40);
    for k = 1:numel(fails)
        ax = subplot(ceil(numel(fails) / 2), 2, k);
        showImage(ax, fails{k}{1}, sprintf('true %s   read %s   (%s)', fails{k}{2}, fails{k}{3}, fails{k}{4}));
    end
    saveFig(fig, ctx, 'failure_cases.png');
end

% ---- screenshots and montage from the earlier runs ------------------------------------------
for f = {'gui_module1.png', 'gui_module2.png', 'gui_module3.png', 'gui_plate.png', 'glyph_montage.png'}
    src = fullfile(ctx.root, 'results', f{1});
    if exist(src, 'file'), copyfile(src, fullfile(ctx.figDir, f{1})); end
end
end

function v = bboxIou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end

function drawPipelineDiagram(ctx)
fig = newFig(1350, 430);
ax = axes(fig, 'Position', [0 0 1 1]);
axis(ax, [0 13.5 0 4.4]);  axis(ax, 'off');  hold(ax, 'on');
col = struct('io', [0.90 0.90 0.90], 'm1', [0.78 0.87 0.98], 'm2', [0.80 0.93 0.80], ...
             'm3', [0.99 0.87 0.72], 'svm', [0.87 0.80 0.95]);
w = 1.85;  h = 0.95;  gap = 0.38;  x0 = 0.25;
top = {'Input photo', 'io'; sprintf('Resize (3 scales),\ncontrast stretch,\nGaussian blur'), 'm1'; sprintf('Vertical Sobel edges,\nOtsu, closing,\nhole filling'), 'm2'; ...
       sprintf('Character rows:\nlocal threshold,\nblob chains'), 'm2'; sprintf('Plate SVM ranks\nthe candidate\nregions'), 'svm'; 'Plate crop', 'io'};
bot = {sprintf('Otsu binarisation,\nconnected\ncomponents'), 'm2'; sprintf('Character group,\nline fit, de-skew'), 'm3'; sprintf('Crop and scale\nto 32 x 32'), 'm3'; ...
       sprintf('HOG features\n(324 values)'), 'svm'; sprintf('One-vs-one\nRBF-SVM\n(630 machines)'), 'svm'; 'Plate text', 'io'};
yT = 2.95;  yB = 0.85;
for k = 1:6
    x = x0 + (k-1) * (w + gap);
    drawBox(ax, x, yT, w, h, top{k,1}, col.(top{k,2}));
    drawBox(ax, x, yB, w, h, bot{k,1}, col.(bot{k,2}));
    if k < 6
        arrow(ax, x + w, yT + h/2, x + w + gap, yT + h/2);
        arrow(ax, x + w, yB + h/2, x + w + gap, yB + h/2);
    end
end
xr = x0 + 5 * (w + gap) + w/2;  xl = x0 + w/2;                 % elbow from the last top box to the first bottom box
plot(ax, [xr xr], [yT, 2.45], 'k-', 'LineWidth', 1.3);
plot(ax, [xr xl], [2.45, 2.45], 'k-', 'LineWidth', 1.3);
plot(ax, [xl xl], [2.45, yB + h + 0.02], 'k-', 'LineWidth', 1.3);
patch(ax, [xl-0.07 xl+0.07 xl], [yB+h+0.14 yB+h+0.14 yB+h], 'k');
names = {'Module 1 - enhancement', 'Module 2 - segmentation', 'Module 3 - geometry', 'SVM', 'Input / output'};
cols = {col.m1, col.m2, col.m3, col.svm, col.io};
for k = 1:5
    xx = 0.6 + (k-1) * 2.5;
    rectangle(ax, 'Position', [xx 0.12 0.25 0.25], 'FaceColor', cols{k}, 'EdgeColor', [0.3 0.3 0.3]);
    text(ax, xx + 0.35, 0.245, names{k}, 'FontSize', 9, 'VerticalAlignment', 'middle', 'Color', [0.1 0.1 0.1]);
end
saveFig(fig, ctx, 'pipeline_diagram.png');
end

function drawBox(ax, x, y, w, h, label, color)
rectangle(ax, 'Position', [x y w h], 'Curvature', 0.18, 'FaceColor', color, 'EdgeColor', [0.3 0.3 0.3], 'LineWidth', 1);
text(ax, x + w/2, y + h/2, label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
     'FontSize', 9, 'Color', [0.1 0.1 0.1]);
end

function arrow(ax, x1, y1, x2, y2)
plot(ax, [x1 x2 - 0.1], [y1 y2], 'k-', 'LineWidth', 1.3);
patch(ax, [x2 - 0.14, x2 - 0.14, x2], [y2 - 0.07, y2 + 0.07, y2], 'k');
end


% =============================================================================
%  section: design experiments (detector closing width, segmentation variants)
% =============================================================================
function S = sec_sweep(ctx)
tpl = ctx.tpl;  te = find(tpl.isTest);

% ---- closing width of the plate detector --------------------------------------------------
N = 60;
rng(11);
scenes = cell(N, 1);  gts = cell(N, 1);
for k = 1:N, [scenes{k}, gts{k}] = makeScene(tpl, te, 'Hard', 0.6); end
cws = [0.04 0.055 0.07 0.09 0.12];
iou50 = zeros(size(cws));  cov95 = iou50;  none = iou50;  miou = iou50;
for q = 1:numel(cws)
    iou = zeros(N, 1);  cov = zeros(N, 1);
    for k = 1:N
        bbox = detectPlate(scenes{k}, 'CloseWidth', cws(q), 'Widths', 640, 'Methods', {'edges'}, 'Verify', false);
        if ~isempty(bbox)
            iou(k) = bboxIou(bbox, gts{k}.bbox);
            cov(k) = coverage(bbox, gts{k}.bbox);
        end
    end
    iou50(q) = nnz(iou > 0.5);  cov95(q) = nnz(cov >= 0.95);  none(q) = nnz(iou == 0);  miou(q) = mean(iou);
    fprintf('    closing width %.3f: %d/%d\n', cws(q), iou50(q), N);
end
S.detect = struct('n', N, 'closeWidth', cws, 'iou50', iou50, 'covered95', cov95, 'none', none, 'meanIoU', miou);

% ---- segmentation variants ---------------------------------------------------------------------
L = load(fullfile(ctx.root, 'models', 'lpr_svm_model_holdout.mat'));  model = L.model;
N2 = 150;
rng(123);
sc = cell(N2, 1);  gt2 = cell(N2, 1);
for k = 1:N2, [sc{k}, gt2{k}] = makeScene(tpl, te, 'Hard', 0.5); end
cfgs = {'Otsu only, height range 0.75-1.33, smoothing on', {'Strategies', {'otsu'}, 'HeightRange', [0.75 1.33], 'Smooth', true}
        'Otsu only, height range 0.65-1.6, smoothing on', {'Strategies', {'otsu'}, 'HeightRange', [0.65 1.6], 'Smooth', true}
        'Otsu + adaptive, height range 0.75-1.33, smoothing on', {'Strategies', {'otsu', 'adaptive'}, 'HeightRange', [0.75 1.33], 'Smooth', true}
        'Otsu + adaptive, height range 0.65-1.6, smoothing on', {'Strategies', {'otsu', 'adaptive'}, 'HeightRange', [0.65 1.6], 'Smooth', true}
        'Adaptive only, height range 0.75-1.33, smoothing on', {'Strategies', {'adaptive'}, 'HeightRange', [0.75 1.33], 'Smooth', true}
        'Otsu only, height range 0.65-1.6, smoothing off (default)', {'Strategies', {'otsu'}, 'HeightRange', [0.65 1.6], 'Smooth', false}};
for c = 1:size(cfgs, 1)
    ok1 = 0;  ok2 = 0;  nseg = 0;
    for k = 1:N2
        res = recognizePlate(sc{k}, model, 'SegOptions', cfgs{c,2});
        ok1 = ok1 + strcmp(res.text, gt2{k}.text);
        nseg = nseg + (res.found && numel(res.text) == numel(gt2{k}.text));
        if res.found
            r2 = recognizePlate(sc{k}, model, 'Plate', res.plate, 'Format', gt2{k}.format, 'SegOptions', cfgs{c,2});
            ok2 = ok2 + strcmp(r2.text, gt2{k}.text);
        end
    end
    S.seg(c) = struct('name', cfgs{c,1}, 'countOk', nseg / N2, 'exactNoFormat', ok1 / N2, 'exactFormat', ok2 / N2);
    fprintf('    %-42s exact %.1f %%\n', cfgs{c,1}, 100 * ok1 / N2);
end
S.segN = N2;
end

function c = coverage(a, g)
% fraction of the ground-truth box that lies inside the detected box
x1 = max(a(1), g(1));  y1 = max(a(2), g(2));
x2 = min(a(1)+a(3), g(1)+g(3));  y2 = min(a(2)+a(4), g(2)+g(4));
c = max(0, x2-x1) * max(0, y2-y1) / (g(3) * g(4));
end


% =============================================================================
%  section: real photographs (images/real) - needs train_real_model first
% =============================================================================
function S = sec_real(ctx)
root = ctx.root;
T = readtable(fullfile(root, 'images', 'real', 'labels.csv'), 'TextType', 'string', 'Delimiter', ',');
base = load(fullfile(root, 'models', 'lpr_svm_model.mat'));      syn = base.model;
D = load(fullfile(root, 'models', 'lpr_svm_model_real_dev.mat')); dev = D.model;
synPlate = syn;  synPlate.plate = dev.plate;
fprintf('    real photos: %d (dev %d, test %d)\n', height(T), nnz(T.split == "dev"), nnz(T.split == "test"));

% ---- the data set ------------------------------------------------------------------------------
src = splitlines(fileread(fullfile(root, 'images', 'real', 'SOURCES.md')));
src = src(startsWith(src, '| car_'));
lic = strings(numel(src), 1);
for k = 1:numel(src)
    c = strtrim(split(src(k), '|'));  lic(k) = c(5);
end
[u, ~, g] = unique(lic);
S.data.n = height(T);  S.data.nDev = nnz(T.split == "dev");  S.data.nTest = nnz(T.split == "test");
S.data.licences = struct('name', cellstr(u), 'count', num2cell(accumarray(g, 1)));
W = zeros(height(T), 1);  Hh = W;
for k = 1:height(T)
    ii = imfinfo(fullfile(root, 'images', 'real', T.file(k)));  W(k) = ii.Width;  Hh(k) = ii.Height;
end
S.data.width = [min(W) max(W)];  S.data.height = [min(Hh) max(Hh)];
S.data.plateLength = [min(strlength(T.plate_text)) max(strlength(T.plate_text))];
fig = newFig(1300, 800);
for k = 1:height(T)
    ax = subplot(7, 7, k);
    A = imread(fullfile(root, 'images', 'real', T.file(k)));
    showImage(ax, imResize(toDouble(A), [90 120], 'bilinear'), '');
    xlabel(ax, char(T.plate_text(k)), 'FontSize', 7, 'Interpreter', 'none');
    if T.split(k) == "test", set(ax, 'XColor', [0.8 0.3 0], 'YColor', [0.8 0.3 0], 'LineWidth', 2, 'Box', 'on'); end
end
saveFig(fig, ctx, 'real_dataset.png');

% ---- the plate SVM and the character SVM ---------------------------------------------------------
S.plateSvm = dev.plate.report;
S.charSvm = dev.report;

% ---- ablation: A-D on the dev and test photos ----------------------------------------------------
cfg = {'A', 'Edge detector, one scale, no verification, synthetic characters', syn,      {'DetectOptions', {'Widths', 640, 'Methods', {'edges'}, 'Verify', false}}
       'B', 'A + several scales, character-row candidates, row check',          syn,      {}
       'C', 'B + plate / not-plate SVM',                                         synPlate, {}
       'D', 'C + real characters in the character SVM',                          dev,      {}};
subs = {'test', 'dev'};
for c = 1:size(cfg, 1)
    for q = 1:2
        R = evaluateReal(cfg{c,3}, 'Subset', subs{q}, 'RecOptions', cfg{c,4});
        S.ablation(c).id = cfg{c,1};  S.ablation(c).name = cfg{c,2};
        S.ablation(c).(subs{q}) = struct('n', R.n, 'read', sum(R.read), 'exact', sum(R.exact), 'charAcc', R.charAccuracy, 'seconds', R.secondsPerImage);
        if c == 4 && q == 1, Rtest = R; end
    end
end
n = S.ablation(4).test.n;  k = S.ablation(4).test.exact;
[S.testExactCI(1), S.testExactCI(2)] = wilson(k, n);

% ---- per-photo results of model D on the test photos -------------------------------------------------
kinds = struct('exact', 0, 'substitution', 0, 'wrongCount', 0, 'noText', 0);
rowsOut = struct('file', {}, 'truth', {}, 'read', {}, 'kind', {});
plates = cell(n, 1);  charsAll = cell(n, 1);  firstOk = 0;
cs = ['0':'9', 'A':'Z'];
Xs = [];  ys = [];
for i = 1:n
    img = imread(fullfile(root, 'images', 'real', Rtest.file(i)));
    res = recognizePlate(img, dev);
    truth = char(Rtest.truth(i));
    if ~res.found || isempty(res.text), kind = 'noText';
    elseif strcmp(res.text, truth),     kind = 'exact';
    elseif numel(res.text) ~= numel(truth), kind = 'wrongCount';
    else, kind = 'substitution'; end
    kinds.(kind) = kinds.(kind) + 1;
    rowsOut(end+1) = struct('file', char(Rtest.file(i)), 'truth', truth, 'read', res.text, 'kind', kind); %#ok<AGROW>
    plates{i} = res.plate;  charsAll{i} = res.chars;
    if strcmp(kind, 'exact') && firstOk == 0, firstOk = i;  okImg = img;  okRes = res; end
    if numel(res.chars) == numel(truth)                         % character-level comparison on well segmented plates
        for q = 1:numel(truth)
            Xs(end+1, :) = hogFeatures(res.chars{q}); ys(end+1, 1) = find(cs == truth(q)); %#ok<AGROW>
        end
    end
end
S.testPhotos = rowsOut;  S.testKinds = kinds;
S.charLevel = struct('n', numel(ys), 'synthetic', mean(svmPredict(syn.svm, Xs) == ys), 'real', mean(svmPredict(dev.svm, Xs) == ys));

% ---- figures -----------------------------------------------------------------------------------------
fig = newFig(1300, 600);
for i = 1:n
    ax = subplot(4, 4, i);
    if isempty(plates{i}), showImage(ax, ones(20, 60), ''); else, showImage(ax, plates{i}, ''); end
    ok = strcmp(rowsOut(i).kind, 'exact');
    if ok, col = [0 0.5 0]; else, col = [0.75 0 0]; end
    title(ax, sprintf('%s  ->  %s', rowsOut(i).truth, rowsOut(i).read), 'FontSize', 8, 'Interpreter', 'none', 'Color', col);
end
saveFig(fig, ctx, 'real_test_plates.png');
if firstOk > 0
    fig = showPipeline(okImg, okRes, 'off');  lightFig(fig);  fig.Position = [0 0 1300 820];
    saveFig(fig, ctx, 'real_pipeline.png');
end
rows = find(~cellfun(@isempty, charsAll), 8);
fig = newFig(1100, 80 * numel(rows));
for q = 1:numel(rows)
    ch = charsAll{rows(q)};  strip = [];
    for j = 1:numel(ch), strip = [strip, 1 - ch{j}, ones(32, 3)]; end %#ok<AGROW>
    ax = subplot(numel(rows), 1, q);  imagesc(ax, strip);  colormap(ax, gray);  axis(ax, 'image', 'off');
    title(ax, sprintf('%s: true %s, read %s', rowsOut(rows(q)).file, rowsOut(rows(q)).truth, rowsOut(rows(q)).read), 'FontSize', 8, 'Interpreter', 'none', 'FontWeight', 'normal');
end
saveFig(fig, ctx, 'real_chars.png');
end

function [lo, hi] = wilson(k, n)
% 95 % Wilson score interval for a proportion k/n
z = 1.96;  p = k / n;
den = 1 + z^2 / n;
c = (p + z^2 / (2 * n)) / den;
h = z * sqrt(p * (1 - p) / n + z^2 / (4 * n^2)) / den;
lo = max(0, c - h);  hi = min(1, c + h);
end
