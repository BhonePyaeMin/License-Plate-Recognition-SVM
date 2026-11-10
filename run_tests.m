function run_tests()
%RUN_TESTS  Self-checks for every module of the toolbox.
%   >> run_tests
%   Prints PASS/FAIL per check and a summary. Needs no toolboxes. The last block
%   evaluates the whole recogniser and needs models/lpr_svm_model_holdout.mat
%   (created by train_lpr_model); it is skipped if that file is missing.

setup_toolbox;
rng(1);
results = {};   % {name, passed}

% ---------------------------- test image -------------------------------------
[x, y] = meshgrid(1:160, 1:120);
G = 0.5 + 0.25*sin(x/9).*cos(y/13) + 0.2*double((x-80).^2 + (y-60).^2 < 900);
G = min(max(G, 0), 1);
I = cat(3, G, 0.8*G, 0.6*G);

% ------------------------------ common ---------------------------------------
check('toDouble: uint8 -> [0,1]', abs(max(toDouble(uint8([0 255]))) - 1) < 1e-12);
check('toDouble: double with small overshoot is left alone', max(toDouble([0.5 1.02])) == 1.02);
check('padImage replicate', isequal(padImage([1 2; 3 4], 1, 1), [1 1 2 2; 1 1 2 2; 3 3 4 4; 3 3 4 4]));

% ------------------------------ module 1 -------------------------------------
low = 0.3 + 0.2*G;
check('histEqualize increases contrast', std(histEqualize(low), 0, 'all') > 2*std(low, 0, 'all'));
check('histMatch moves mean towards reference', abs(mean(histMatch(G, 0.7*G + 0.3), 'all') - mean(0.7*G + 0.3, 'all')) < 0.02);
check('grayTransform negative', max(abs(grayTransform(G, 'negative') - (1 - G)), [], 'all') < 1e-12);
noisy = addNoise(G, 'saltpepper', 0.1);
[~, pMed]  = imageMetrics(G, smoothFilter(noisy, 'median', 3));
[~, pMean] = imageMetrics(G, smoothFilter(noisy, 'mean', 3));
check('median beats mean on salt-and-pepper noise', pMed > pMean + 3);
check('Gaussian filter preserves constant image', max(abs(smoothFilter(0.4*ones(20), 'gaussian', 5) - 0.4), [], 'all') < 1e-12);
check('Laplacian sharpening increases edge energy', ...
      std(spatialFilter(sharpenFilter(G, 'laplacian', 1), [0 1 0; 1 -4 1; 0 1 0]), 0, 'all') > ...
      std(spatialFilter(G, [0 1 0; 1 -4 1; 0 1 0]), 0, 'all'));
lp = freqFilter(G, 'lowpass', 0.1, 'gaussian');
hp = freqFilter(G, 'highpass', 0.1, 'gaussian');
check('FFT low-pass smooths, high-pass sharpens', ...
      std(spatialFilter(lp, [-1 0 1]), 0, 'all') < std(spatialFilter(G, [-1 0 1]), 0, 'all') && ...
      std(spatialFilter(hp, [-1 0 1]), 0, 'all') > 0.5*std(spatialFilter(G, [-1 0 1]), 0, 'all'));
check('FFT filters work on RGB', isequal(size(freqFilter(I, 'bandpass', [0.05 0.3])), size(I)));

% ------------------------------ module 2 -------------------------------------
bw = rand(60, 70) > 0.55;
[L, n] = labelComponents(bw, 8);
check('labelComponents matches flood-fill reference', n == floodCount(bw));
step = zeros(40, 40);  step(:, 21:end) = 1;
check('Sobel/Prewitt/Canny find the step edge', all(arrayfun(@(m) ...
      all(ismember(find(any(edgeDetect(step, m{1}), 1)), [20 21])), {'sobel', 'prewitt', 'canny'})));
check('Otsu separates a bimodal histogram', abs(otsuThreshold([0.2*ones(1, 50), 0.8*ones(1, 50)]) - 0.5) < 0.02);
A = rand(30, 40) > 0.7;  SE = makeSE('rect', [3 5]);
check('dilation equals convolution', isequal(morphOp(A, 'dilate', SE), conv2(double(A), double(SE), 'same') > 0));
check('erosion is the dual of dilation', isequal(morphOp(A, 'erode', SE), ~morphOp(~A, 'dilate', SE)));
check('opening is anti-extensive, closing extensive', all(morphOp(A, 'open', SE) <= A, 'all') && all(morphOp(A, 'close', SE) >= A, 'all'));
check('fillHoles fills an enclosed hole', all(fillHoles([1 1 1; 1 0 1; 1 1 1] > 0), 'all'));
flat = zeros(50);  flat(10:40, 10:40) = 0.8;
check('region growing fills exactly the flat square', isequal(regionGrow(flat, [25 25], 0.1), flat > 0.5));
check('colour segmentation finds pure yellow', all(colorSegment(cat(3, ones(4), 0.85*ones(4), 0.1*ones(4)), 'HSV', 'yellow'), 'all'));

% ------------------------------ module 3 -------------------------------------
check('rotate 90 deg equals rot90', max(abs(geometricTransforms(G, 'rotate', 90, 'nearest', 'full') - rot90(G)), [], 'all') < 1e-12);
shifted = geometricTransforms(G, 'translate', 5, 3, 'nearest');
check('translation moves pixels', isequal(shifted(4:end, 6:end), G(1:end-3, 1:end-5)));
fwd = warpImage(G, eye(3), size(G), 'bilinear', 'forward');
check('forward bilinear mapping with identity keeps the image', max(abs(fwd - G), [], 'all') < 1e-9);
jf = warpImage(ones(60, 80), diag([1.6 1.6 1]), [60 80], 'nearest',  'forward', 0);
jr = warpImage(ones(60, 80), diag([1.6 1.6 1]), [60 80], 'bilinear', 'reverse', 0);
check('forward mapping leaves holes, reverse mapping does not', mean(jf(3:end, 3:end) == 0, 'all') > 0.2 && all(jr(3:end, 3:end) > 0, 'all'));
ramp = repmat(linspace(0, 1, 50), 40, 1);
check('bilinear interpolates a ramp exactly', abs(interpSample(ramp, 10.5, 5.2, 'bilinear') - mean(ramp(1, 10:11))) < 1e-12);
check('bicubic interpolates a ramp exactly', abs(interpSample(ramp, 10.5, 5.2, 'bicubic') - mean(ramp(1, 10:11))) < 1e-9);
check('imResize round trip keeps the image', imageMetricsPsnr(G, imResize(imResize(G, 0.5, 'bicubic'), size(G), 'bicubic')) > 20);
Jd = radialDistortion(G, -0.25, 0, 'apply');  Jc = radialDistortion(Jd, -0.25, 0, 'correct');
check('radial distortion round trip', imageMetricsPsnr(G(30:90, 40:120), Jc(30:90, 40:120)) > 30);
Jd3 = radialDistortion(G, -0.3, 0, 'apply');  Jc3 = radialDistortion(Jd3, -0.3, 0, 'correct');
check('strong barrel distortion: finite result, centre recovered, unreachable corners left black', ...
      all(isfinite(Jd3), 'all') && imageMetricsPsnr(G(40:80, 50:110), Jc3(40:80, 50:110)) > 30 && Jd3(1, 1) == 0 && Jd3(end, end) == 0);
Gt = min(max(G + 0.6*(smoothFilter(rand(120, 160), 'gaussian', 7, 1.2) - 0.5), 0), 1);   % textured test image
mov = geometricTransforms(geometricTransforms(Gt, 'rotate', 5), 'translate', 6, -4);
[~, reg] = registerImages(Gt, mov, 'features');
check('feature registration reduces the error', imageMetricsPsnr(Gt(25:95, 30:130), reg(25:95, 30:130)) > imageMetricsPsnr(Gt(25:95, 30:130), mov(25:95, 30:130)) + 3);
[~, ~, inf2] = registerImages(G, geometricTransforms(G, 'translate', 7, -3, 'nearest'), 'phase');
check('phase correlation recovers the shift', isequal(inf2.shift, [-7 3]));

% -------------------------------- SVM ----------------------------------------
t = 2*pi*rand(300, 1);  r = [ones(150, 1); 2.2*ones(150, 1)] + 0.12*randn(300, 1);
Xc = [r.*cos(t), r.*sin(t)];  yc = [ones(150, 1); -ones(150, 1)];
kp = struct('type', 'rbf', 'gamma', 1);
mb = svmTrainBinary(Xc(1:2:end, :), yc(1:2:end), 10, kp);
f = kernelMatrix(Xc(2:2:end, :), Xc(1:2:end, :), kp) * sparseCoef(mb, 150) + mb.b;
check('binary RBF-SVM separates concentric circles', mean(sign(f) == yc(2:2:end)) > 0.95);
check('SMO keeps sum(alpha*y) = 0', abs(sum(mb.coef)) < 1e-8);
check('HOG descriptor length is 324', numel(hogFeatures(zeros(32))) == 324);
check('HOG with signed orientations (18 bins over 360 degrees) has 648 values, unsigned HOG is unchanged', ...
      numel(hogFeatures(zeros(32), 8, 18, true)) == 648 && numel(hogFeatures(zeros(32), 8, 9, false)) == 324);
hA = zeros(32);  hA(8:24, 8:12) = 1;  hA(8:12, 8:24) = 1;                          % an L-shaped pattern and its upside-down copy
check('signed HOG tells a pattern from its upside-down copy better than unsigned HOG', ...
      norm(hogFeatures(hA, 8, 18, true) - hogFeatures(flipud(hA), 8, 18, true)) > norm(hogFeatures(hA) - hogFeatures(flipud(hA))));

% ------------------------- license plate pipeline ----------------------------
tpl = buildGlyphTemplates(fullfile('models', 'glyph_templates.mat'));
[img, gt] = makeScene(tpl, find(~tpl.isTest), 'Text', 'ABC 1234', 'Hard', 0.2);
check('makeScene returns a plate box inside the image', all(gt.bbox(1:2) >= 1) && gt.bbox(1) + gt.bbox(3) <= size(img, 2));
bbox = detectPlate(img);
check('detectPlate finds the plate (IoU > 0.5)', ~isempty(bbox) && bboxIou(bbox, gt.bbox) > 0.5);

hf = fullfile('models', 'lpr_svm_model_holdout.mat');
if exist(hf, 'file')
    M = load(hf);
    R = evaluateLPR(M.model, 'N', 40, 'Hard', 0.4, 'Seed', 5);
    check('pipeline: plate detection >= 90 % on unseen fonts', R.detectionRate >= 0.90);
    check('pipeline: character accuracy (format known) >= 90 %', R.charAccuracyWithFormat >= 0.90);
    check('pipeline: exact plates (format known) >= 70 %', R.plateAccuracyWithFormat >= 0.70);
else
    fprintf('SKIP  end-to-end evaluation (run train_lpr_model first)\n');
end

% ------------------------------- real photographs ----------------------------------
check('editDistance: kitten -> sitting = 3', editDistance('kitten', 'sitting') == 3);
labelFile = fullfile('images', 'real', 'labels.csv');
if exist(labelFile, 'file')
    Tl = readtable(labelFile, 'TextType', 'string', 'Delimiter', ',');
    check('real photos: every labelled file exists and has a valid plate text', ...
          all(arrayfun(@(f) exist(fullfile('images', 'real', f), 'file') == 2, Tl.file)) && ...
          all(~cellfun(@isempty, regexp(cellstr(Tl.plate_text), '^[0-9A-Z]{3,9}$', 'once'))));
    check('real photos: dev and test splits are disjoint and non-empty', ...
          any(Tl.split == "dev") && any(Tl.split == "test") && all(ismember(Tl.split, ["dev", "test"])));
else
    fprintf('SKIP  real-photo checks (images/real not found)\n');
end
devModel = fullfile('models', 'lpr_svm_model_real_dev.mat');
if exist(devModel, 'file') && exist(labelFile, 'file')
    D = load(devModel);
    pm = D.model.plate;
    sPlate = plateScore(pm, renderPlate('ABC 1234', tpl, 1, 'Height', 80));
    sBack = plateScore(pm, rand(60, 200, 3));
    check('plate SVM: a rendered plate scores higher than random noise', sPlate > sBack);
    Rt = evaluateReal(D.model, 'Subset', 'test');
    check('real photos (held-out test split): character accuracy >= 40 %', Rt.charAccuracy >= 0.40);
    check('real photos (held-out test split): at least 3 plates read exactly', sum(Rt.exact) >= 3);
else
    fprintf('SKIP  held-out real-photo evaluation (run train_real_model first)\n');
end

% --------------------------- exposure and multi-plate --------------------------------
Gn = 0.05 + 0.9 * G;                                             % normal exposure: median ~0.5, wide range
[Jn, infoN] = normalizeExposure(Gn);
check('normalizeExposure leaves a normally exposed image alone', ~infoN.applied && isequal(Jn, Gn));
[Jd, infoD] = normalizeExposure(0.04 + 0.1 * G);                 % very dark: repaired
check('normalizeExposure brightens a very dark image (median -> about 0.5)', infoD.applied && abs(median(Jd(:)) - 0.5) < 0.1);
[Jb, infoB] = normalizeExposure(min(1, 0.8 + 0.2 * G));          % washed out: repaired
check('normalizeExposure darkens a washed-out image', infoB.applied && median(Jb(:)) < median(min(1, 0.8 + 0.2 * G), 'all'));
% plate-only photos: the whole image is a plate, slightly tilted
rng(3);
[plOnly, ~] = renderPlate('ABC 1234', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'white');
plOnly = padImage(plOnly, 40, 40, 'replicate');
plOnly = geometricTransforms(plOnly, 'rotate', 5, 'bilinear');
plOnly = plOnly(41:end-40, 41:end-40, :);
[isCl, ~] = isPlateCloseup(plOnly);
check('isPlateCloseup recognises a tilted plate photo', isCl);
check('isPlateCloseup rejects an ordinary scene', ~isPlateCloseup(makeScene(tpl, find(~tpl.isTest), 'Hard', 0.2)));
if exist(fullfile('models', 'lpr_svm_model_real.mat'), 'file')
    F0 = load(fullfile('models', 'lpr_svm_model_real.mat'));
    r0 = recognizePlate(plOnly, F0.model);
    check('a tilted plate-only photo is read exactly (ABC1234) without a plate search', strcmp(r0.text, 'ABC1234') && isequal(r0.bbox, [1 1 size(plOnly, 2) size(plOnly, 1)]));
end
Xh = makeHardNegatives(tpl, 8);
check('makeHardNegatives returns one finite 1620-value feature row per example', isequal(size(Xh), [8 1620]) && all(isfinite(Xh), 'all'));
finalModel = fullfile('models', 'lpr_svm_model_real.mat');
if exist(finalModel, 'file') && exist(fullfile('images', 'real', 'car_18.jpg'), 'file')
    F = load(finalModel);
    outP = recognizePlates(imread(fullfile('images', 'real', 'car_18.jpg')), F.model);
    check('recognizePlates returns plates with box, text and reliability flag', ...
          ~isempty(outP) && all(isfield(outP, {'box', 'text', 'conf', 'score', 'width', 'reliable', 'lines', 'charH'})));
    nested = false;                                          % no read plate lies inside another one (wide box around a plate and its tail lights)
    for q1 = 1:numel(outP)
        for q2 = q1 + 1:numel(outP)
            b1 = outP(q1).box;  b2 = outP(q2).box;
            ov = max(0, min(b1(1) + b1(3), b2(1) + b2(3)) - max(b1(1), b2(1))) * max(0, min(b1(2) + b1(4), b2(2) + b2(4)) - max(b1(2), b2(2)));
            if ov / min(b1(3) * b1(4), b2(3) * b2(4)) > 0.6, nested = true; end
        end
    end
    check('recognizePlates: no read plate lies (mostly) inside another read plate', ~nested);
else
    fprintf('SKIP  multi-plate check (needs models/lpr_svm_model_real.mat and images/real)\n');
end

% ------------------- hard crops, sliding windows, plate boxes -----------------------------
rng(5);
nBest = 0;  nDef = 0;
for t = 1:4                                                      % dim yellow plate under a bright car body
    [plD, ~] = renderPlate('ABC 1234', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'yellow');
    cropD = [ones(40, size(plD, 2), 3); 0.55 * plD];
    nDef  = nDef  + (numel(segmentChars(cropD)) == 7);
    nBest = nBest + (numel(segmentPlateBest(cropD)) == 7);
end
check('segmentPlateBest: a dim plate under a bright body is cut into 7 characters (default Otsu fails)', nBest >= 3 && nDef < nBest);
boxFile = fullfile('images', 'real', 'plate_boxes.csv');
if exist(boxFile, 'file') && exist(labelFile, 'file')
    PBt = readtable(boxFile, 'TextType', 'string');
    check('plate_boxes.csv: one positive box per labelled photo', ...
          isequal(sort(PBt.file), sort(Tl.file)) && all(PBt.w > 0 & PBt.h > 0 & PBt.x > 0 & PBt.y > 0));
end
if exist(finalModel, 'file')
    F1 = load(finalModel);
    [imgW, gtW] = makeScene(tpl, find(tpl.isTest), 'Hard', 0.3);
    [winC, mined] = slidingPlateCandidates(toDouble(imgW), F1.model.plate, 'GT', gtW.bbox, 'MinScore', -2);
    iouW = arrayfun(@(c) bboxIou(c.box, gtW.bbox), winC(1:min(5, numel(winC))));
    check('slidingPlateCandidates: a synthetic plate is among the 5 best windows (IoU > 0.3)', ~isempty(iouW) && max(iouW) > 0.3);
    check('slidingPlateCandidates mining mode returns 1620-value positives and hard negatives', ...
          size(mined.Xpos, 2) == 1620 && size(mined.Xneg, 2) == 1620 && size(mined.Xpos, 1) >= 1 && size(mined.Xneg, 1) >= 1);
    resN = recognizePlate(rand(120, 160, 3), F1.model);
    check('recognizePlate on noise: nothing read, fields found / guess present', ~resN.found && isfield(resN, 'guess'));
    if exist(fullfile('images', 'real', 'car_07.jpg'), 'file')
        r07 = recognizePlate(imread(fullfile('images', 'real', 'car_07.jpg')), F1.model);
        check('car_07 (yellow plate, dim, a photo that used to give "No plate found"): plate found, text within 2 edits of DR3898', ...
              r07.found && editDistance(r07.text, 'DR3898') <= 2);
    end
end

% ------------- junk rejection, chosen car, minimum width, night --------------------------
XhAll = makeHardNegatives(tpl, 18);                              % two of each of the nine kinds
check('makeHardNegatives: all nine kinds give finite 1620-value features', isequal(size(XhAll), [18 1620]) && all(isfinite(XhAll), 'all'));
check('pickCarROI and markPlateBoxes exist (they need mouse clicks, so they are not run here)', ...
      exist('pickCarROI', 'file') == 2 && exist('markPlateBoxes', 'file') == 2);
Jl = simulateNight(Gn, 'lit', 1);  Jd = simulateNight(Gn, 'dark', 1);
check('simulateNight: dark < lit < original luminance, repeatable for the same seed', ...
      median(Jd(:)) < median(Jl(:)) && median(Jl(:)) < median(Gn(:)) && isequal(simulateNight(Gn, 'lit', 1), Jl));
if exist(finalModel, 'file')
    F2 = load(finalModel);
    plA = renderPlate('AB1', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'white');   % a 3-character label
    rA = recognizePlate(plA, F2.model, 'Plate', plA);
    check('recognizePlate: 3 characters (a route label) are not a plate (MinChars), chars are kept for display', ...
          ~rA.found && isempty(rA.text) && startsWith(rA.reason, 'only 3') && numel(rA.chars) == 3);
    plB = renderPlate('ABC 1234', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'white');
    rB = recognizePlate(plB, F2.model, 'Plate', plB, 'Format', 'LL DD');
    rC = recognizePlate(plB, F2.model, 'Plate', plB, 'Format', 'LLL DDDD');
    check('recognizePlate: a layout of another length is "format mismatch", the right layout reads', ...
          ~rB.found && strcmp(rB.reason, 'format mismatch') && rC.found && numel(rC.text) == 7);
    check('recognizePlate: MinConf above the confidence gives "low confidence"', ...
          ~recognizePlate(plB, F2.model, 'Plate', plB, 'MinConf', 1.01).found);
    if exist(fullfile('images', 'failures', 'hk_sign_crop.jpg'), 'file')
        rS = recognizePlate(imread(fullfile('images', 'failures', 'hk_sign_crop.jpg')), F2.model);
        rT = recognizePlate(imread(fullfile('images', 'failures', 'hk_traffic.jpg')), F2.model);
        check('hk_traffic.jpg and its blue sign with the "8C" route label: no plate found', ~rS.found && ~rT.found);
    end
    if exist(fullfile('images', 'real', 'car_18.jpg'), 'file')
        img18 = imread(fullfile('images', 'real', 'car_18.jpg'));
        r18 = recognizePlate(img18, F2.model);
        roi18 = [max(1, r18.bbox(1) - 300), max(1, r18.bbox(2) - 400), r18.bbox(3) + 600, r18.bbox(4) + 700];
        r18b = recognizePlate(img18, F2.model, 'ROI', roi18);
        check('recognizePlate ROI: the plate of the chosen car is found, boxes are in full-photo coordinates', ...
              r18b.found && strcmp(r18b.text, r18.text) && all(r18b.bbox(1:2) >= roi18(1:2)) && bboxIou(r18b.bbox, r18.bbox) > 0.5);
        r18c = recognizePlate(img18, F2.model, 'MinPlateWidth', 10000);
        check('recognizePlate MinPlateWidth: a plate narrower than the limit is not read, its box is kept in guess', ...
              ~r18c.found && isempty(r18c.text) && startsWith(r18c.reason, 'plate too small') && numel(r18c.guess) == 4);
    end
end
if exist(devModel, 'file') && exist(labelFile, 'file')
    check('evaluateReal reports day and night separately (note = night marks night photos)', ...
          isfield(Rt, 'day') && isfield(Rt, 'night') && Rt.day.n + Rt.night.n == Rt.n);
end

% ----------------------- perspective correction (homography) -------------------------
rng(2);
Htrue = [1.1 0.15 8; -0.1 0.95 -5; 4e-4 -3e-4 1];
srcP = [1 1; 200 1; 200 70; 1 70];
pp = Htrue * [srcP.'; ones(1, 4)];  dstP = (pp(1:2, :) ./ pp(3, :)).';
[Hest, errH] = homography(srcP, dstP);
check('homography: 4 point pairs give the projective matrix back (DLT/SVD)', errH < 1e-8 && max(abs(Hest(:) - Htrue(:) / Htrue(3, 3))) < 1e-6);
srcN = [srcP; 100 35; 60 20];  pn = Htrue * [srcN.'; ones(1, 6)];  dstN = (pn(1:2, :) ./ pn(3, :)).' + 0.05 * randn(6, 2);
[~, errN] = homography(srcN, dstN);
check('homography: 6 noisy pairs (least squares) fit within the noise', errN < 0.2);
Gp = G(20:95, 30:130);
Wp = warpImage(Gp, Hest, [90 230], 'bilinear', 'reverse', 0);
Bk = warpImage(Wp, inv(Hest), size(Gp), 'bilinear', 'reverse', 0);
check('warpImage accepts a projective matrix: warping forth and back restores the image', imageMetricsPsnr(Gp(15:end-15, 15:end-15), Bk(15:end-15, 15:end-15)) > 25);
holdFile = fullfile('models', 'lpr_svm_model_holdout.mat');
if exist(holdFile, 'file')
    Hm = load(holdFile);
    Ry = evaluateYaw(Hm.model, 'Angles', [0 30 40], 'N', 12, 'Seed', 5, 'Modes', 1:2);              % tight crops
    check('rectification, tight crops of synthetic plates at yaw 0/30/40: automatic mode loses at most one plate in six', ...
          all(Ry.rate(:, 2) >= Ry.rate(:, 1) - 1 / 6));
    Rl = evaluateYaw(Hm.model, 'Angles', [30 40], 'N', 12, 'Seed', 5, 'Modes', 1:2, 'Crop', 'loose');
    check('rectification, loose crops (plate in a big grey surrounding) at yaw 30 and 40: automatic mode reads more plates', ...
          sum(Rl.rate(:, 2)) > sum(Rl.rate(:, 1)));
end
% rectifyPlate on a plate turned by hand into a trapezoid: outline found, upright 80-row result that reads
rng(4);
[plY, ~] = renderPlate('ABC 1234', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'white');
[hY, wY, ~] = size(plY);
canvasY = 0.5 * ones(hY + 60, wY + 60, 3);  canvasY(31:30+hY, 31:30+wY, :) = plY;
[hC, wC, ~] = size(canvasY);
HY = homography([1 1; wC 1; wC hC; 1 hC], [1 + 6, 1 + 10; wC - 6, 1; wC - 6, hC; 1 + 6, hC - 10]);
imgY = warpImage(canvasY, HY, [hC wC], 'bilinear', 'reverse', 0.5);
[rectY, okY, infoY] = rectifyPlate(imgY);
check('rectifyPlate: finds the outline of a perspective-distorted plate, upright 80-row result', ...
      okY && size(rectY, 1) == 80 && infoY.distortion > 4 && infoY.aspect > 3 && infoY.aspect < 7.5);
charsY = segmentPlateBest(rectY);
check('rectifyPlate: the straightened plate is cut into its 7 characters', numel(charsY) == 7);
[~, okN] = rectifyPlate(0.5 * ones(120, 400, 3));
check('rectifyPlate: a uniform crop has no plate outline (the old path is kept)', ~okN);

% ------------------------------ pre-filter panel ---------------------------------
rng(8);
Gs = G(10:90, 10:130);
psnrOf = @(A) imageMetricsPsnr(Gs, A);
spn = addNoise(Gs, 'saltpepper', 0.08);
check('median filter beats mean and Gaussian filters on salt-and-pepper noise by > 3 dB', ...
      psnrOf(smoothFilter(spn, 'median', 3)) > psnrOf(smoothFilter(spn, 'mean', 3)) + 3 && ...
      psnrOf(smoothFilter(spn, 'median', 3)) > psnrOf(smoothFilter(spn, 'gaussian', 5, 1)) + 3);
step = [zeros(40, 30), ones(40, 30)];  stepN = min(max(step + 0.08 * randn(size(step)), 0), 1);
gB = abs(diff(bilateralFilter(stepN, 1.5, 0.15), 1, 2));  gG = abs(diff(spatialFilter(stepN, gaussianKernel(5, 1.2)), 1, 2));
check('bilateral filter keeps a step edge sharper than a Gaussian filter of similar noise reduction', ...
      max(gB(20, :)) > 1.5 * max(gG(20, :)) && std(reshape(bilateralFilter(stepN, 1.5, 0.15) - step, [], 1)) < std(stepN(:) - step(:)));
lowc = 0.5 + 0.25 * (Gs - 0.5);
Jl = localHistEqualize(lowc, 4, 3);
check('local histogram equalisation (CLAHE) raises the contrast of a flat picture and stays in [0,1]', ...
      std(Jl(:)) > 2 * std(lowc(:)) && min(Jl(:)) >= 0 && max(Jl(:)) <= 1 && isequal(size(Jl), size(lowc)));
[gx, ~] = meshgrid(linspace(0, 1, size(Gs, 2)), 1:size(Gs, 1));
shaded = Gs .* (0.25 + 0.75 * gx);
blkSpread = @(A) std(reshape(mean(reshape(A(1:80, 1:120), 10, 8, 20, 6), [1 3]), [], 1)) / mean(A(:));
check('illumination correction removes a lighting ramp (spread of the block means falls by half)', ...
      blkSpread(illuminationCorrect(shaded, 40, 1)) < 0.5 * blkSpread(shaded));
[cx, cy] = meshgrid(1:120, 1:80);
chk = 0.2 + 0.6 * double(mod(floor(cx / 5) + floor(cy / 5), 2) == 0);                 % squares with sharp edges
blurC = spatialFilter(chk, gaussianKernel(9, 1.5), 'symmetric');
check('Richardson-Lucy deblurring raises the PSNR of a blurred picture', imageMetricsPsnr(chk, deblurRL(blurC, 1.5, 10)) > imageMetricsPsnr(chk, blurC) + 1);
oneP = ones(20);
bz = spatialFilter(oneP, ones(3) / 9, 'zero');  br = spatialFilter(oneP, ones(3) / 9, 'replicate');
check('border padding: zero padding darkens the border, replicate keeps it; the interior is identical', ...
      bz(1, 1) < 0.5 && abs(br(1, 1) - 1) < 1e-12 && isequal(bz(3:end-2, 3:end-2), br(3:end-2, 3:end-2)));
pfs = prefilterOps();  smallRGB = rand(40, 60, 3);  okAll = true;
for q = 1:numel(pfs)
    pv = arrayfun(@(t) t.default, pfs(q).params);
    Jq = pfs(q).run(smallRGB, pv, 'replicate', [0 0 0; 0 1 0; 0 0 0]);
    okAll = okAll && all(isfinite(Jq(:))) && min(Jq(:)) >= 0 && max(Jq(:)) <= 1 && size(Jq, 3) == 3 && ...
            (isequal(size(Jq), size(smallRGB)) || strncmp(pfs(q).name, 'Resize', 6));
end
check('every pre-filter (17) runs on a colour picture and returns values in [0,1]', okAll && numel(pfs) >= 17);
chainT = struct('name', {'Median filter', 'Gamma correction', 'Resize (change the resolution)'}, 'p', {3, 0.7, [2 2]});
[JT, repT] = applyPrefilters(smallRGB, chainT);
check('applyPrefilters runs the chain in order, one report line per stage, Resize changes the size', ...
      numel(repT) == 3 && isequal(size(JT), [80 120 3]));
chainT(2).enabled = false;  chainT(1).enabled = true;  chainT(3).enabled = true;
check('applyPrefilters: a stage with enabled = false is skipped', numel(nthOut(2, @applyPrefilters, smallRGB, chainT)) == 2);
check('applyPrefilters: identity kernel gives the picture back, an even-sized kernel is refused', ...
      max(abs(applyPrefilters(smallRGB, struct('name', 'Convolution with my own kernel', 'p', []), 'Kernel', [0 0 0; 0 1 0; 0 0 0]) - smallRGB), [], 'all') < 1e-12 && ...
      throwsError(@() applyPrefilters(smallRGB, struct('name', 'Convolution with my own kernel', 'p', []), 'Kernel', ones(2))));
chS = suggestPrefilters(spn);  chG = suggestPrefilters(min(max(Gs + 0.07 * randn(size(Gs)), 0), 1));
chD = suggestPrefilters(0.1 * Gs, true);  chL = suggestPrefilters(lowc, true);  chC = suggestPrefilters(Gs);
[chD0, rsD0] = suggestPrefilters(0.1 * Gs);
check('suggestPrefilters: salt-and-pepper -> median, Gaussian noise -> bilateral', ...
      any(strcmp({chS.name}, 'Median filter')) && any(strcmp({chG.name}, 'Bilateral filter (edge-preserving)')));
check('suggestPrefilters: dark / flat photos get gamma / stretching only on request (the recogniser repairs exposure itself)', ...
      any(strcmp({chD.name}, 'Gamma correction')) && any(strcmp({chL.name}, 'Contrast stretching')) && isempty(chD0) && contains(strjoin(rsD0), 'repairs this itself'));
check('suggestPrefilters: a normal photo gets no filter', isempty(chC));
appF = LPR_Toolbox('Visible', 'off');
appF.loadImage(rand(60, 90, 3), 'test');
appF.setFilters(struct('name', {'Median filter', 'Resize (change the resolution)'}, 'p', {3, [2 2]}), 'symmetric');
appF.previewFilters();
stF = appF.state();
check('GUI filter panel: preview applies the chain to the original (median, then resize x2 gives 120 x 180)', isequal(size(stF.filtered), [120 180 3]) && isequal(size(stF.orig), [60 90 3]));
appF.clearFilters();
stF = appF.state();
check('GUI filter panel: "Remove filters" restores the original photo as the input', isempty(stF.filtered) && isequal(stF.I, stF.orig));
close(appF.fig);

% ------------------ streaks are not characters (character-validity SVM) -------------------
if exist(finalModel, 'file')
    F3 = load(finalModel);
    cvm = F3.model.charValid;
    rng(6);
    [plV, ~] = renderPlate('ABC 1234', tpl, find(~tpl.isTest, 1), 'Height', 100, 'Style', 'white');
    charsV = segmentChars(plV);
    junk = cell(1, 5);                                                    % slanted thin stripes of a wall / van body
    for q = 1:5
        [jx, jy] = meshgrid(1:40, 1:60);
        stripe = abs((jx - 8) - 0.35 * (jy - 30) - 3 * q) < 2.2;
        junk{q} = normalizeChar(stripe, 32);
    end
    [okR, sR] = charsLookValid(cvm, charsV);
    [okJ, sJ] = charsLookValid(cvm, junk);
    check('character-validity SVM: the characters of a plate look valid, slanted stripes do not', okR && ~okJ && mean(sR) > mean(sJ) + 0.5);
    wall = 0.25 * ones(80, 300);                                          % a plate-sized wall with 5 slanted bright stripes
    [wx, wy] = meshgrid(1:300, 1:80);
    for q = 1:5, wall(abs((wx - 40 * q) - 0.35 * (wy - 40)) < 3) = 0.85; end
    rW = recognizePlate(repmat(wall, [1 1 3]), F3.model, 'Plate', repmat(wall, [1 1 3]));
    check('recognizePlate: a row of stripes is refused ("characters look like streaks or noise")', ~rW.found && isempty(rW.text));
    if exist(fullfile('images', 'failures', 'hk_traffic_user.jpg'), 'file')
        rK = recognizePlate(imread(fullfile('images', 'failures', 'hk_traffic_user.jpg')), F3.model);
        rN = recognizePlate(imread(fullfile('images', 'failures', 'night_traffic_user.jpg')), F3.model);
        check('user photos: the van of the Hong Kong photo is not boxed as a plate, the Mini of the night photo is read', ...
              ~rK.found && rN.found && strcmp(rN.text, 'T935AK797'));
    end
end

% -------------------- filter panel and plate tab of the GUI --------------------
pfNames = {prefilterOps().name};
helpText = strjoin({pfs.help}, ' ');
check('filter help is English only (no characters beyond ASCII), every filter has a help text and short labels', ...
      all(double(helpText) < 128) && all(cellfun(@(t) numel(t) > 40, {pfs.help})) && ...
      all(arrayfun(@(o) all(arrayfun(@(q) numel(q.label) <= 16 && ~isempty(q.tip), o.params)), pfs)));
appG = LPR_Toolbox('Visible', 'off');
appG.loadImage(rand(60, 90, 3), 'chooser test');
ddG = findall(appG.fig, 'Type', 'uidropdown');
btnG = findall(appG.fig, 'Type', 'uibutton');
cbG = findall(appG.fig, 'Type', 'uicheckbox');
check('GUI: the situation chooser and "Use recommended" are gone; no "Filter guide" button, no Myanmar text; "Enlarge text" is there', ...
      ~any(arrayfun(@(d) any(contains(string(d.Items), 'Small or far plate')), ddG)) && ~any(arrayfun(@(b) strcmp(b.Text, 'Use recommended'), btnG)) && ...
      ~any(arrayfun(@(b) contains(b.Text, 'guide', 'IgnoreCase', true), btnG)) && any(arrayfun(@(b) strcmp(b.Text, 'Enlarge text'), btnG)));
check('GUI plate tab: "Find ALL plates" and "Car by car" are ticked by default, "Night vision" is there (not ticked), and a "Show plate" list', ...
      any(arrayfun(@(c) startsWith(c.Text, 'Find ALL') && c.Value, cbG)) && any(arrayfun(@(c) startsWith(c.Text, 'Car by car') && c.Value, cbG)) && ...
      any(arrayfun(@(c) startsWith(c.Text, 'Night vision') && ~c.Value, cbG)) && any(arrayfun(@(d) any(strcmp(d.Items, '-')), ddG)));
cbAll = cbG(arrayfun(@(c) startsWith(c.Text, 'Find ALL'), cbG));
appG.setFilters(struct('name', 'Median filter', 'p', 3), 'replicate');
appG.previewFilters();
stG = appG.state();
check('GUI: a median filter put into Filter 1 gives a preview of the same size that is not the original', ...
      isequal(size(stG.filtered), size(stG.orig)) && max(abs(stG.filtered(:) - stG.orig(:))) > 1e-6);
appG.suggestFilters();
scrT = get(0, 'ScreenSize');
bigG = appG.enlargeText();
taBig = findall(bigG, 'Type', 'uitextarea');
check('GUI: "Enlarge text" opens a big window with the text of the panel in a large font', ...
      ~isempty(taBig) && taBig.FontSize >= 16 && numel(taBig.Value) >= 2 && bigG.Position(3) > 0.5 * scrT(3));
close(bigG);
appG.loadImage(rand(60, 90, 3), 'chooser test 2');
appG.setFilters(struct('name', 'Resize (change the resolution)', 'p', [2 3]), 'replicate');
appG.recognize();                                                         % "Recognise plate" then reads the filtered photo
stG = appG.state();
check('GUI: "Recognise plate" reads the filtered photo (here enlarged 2 times)', isequal(size(stG.I), [120 180 3]) && isequal(size(stG.orig), [60 90 3]));
appG.loadImage(rand(60, 90, 3), 'chooser test 3');
appG.recognize();
stG = appG.state();
check('GUI: after loading a new photo "Recognise plate" works on the original size (no filter is left over)', isequal(size(stG.I), [60 90 3]));
cbAll.Value = false;                                                       % one plate at a time
appG.setFilters(struct('name', 'Median filter', 'p', 3), 'replicate');
appG.recognizeFiltered();
stG = appG.state();
tasG = findall(appG.fig, 'Type', 'uitextarea');
check('GUI: "Recognise on filtered photo" on a photo without a plate says that the original gives no plate either', ...
      ~stG.lastRes.found && any(arrayfun(@(t) any(contains(string(t.Value), 'original photo gives no plate')), tasG)));
jf = fullfile(tempdir, 'lpr_test_photo.jfif');
tmpJ = [tempname '.jpg'];  imwrite(uint8(255 * rand(40, 50, 3)), tmpJ);
copyfile(tmpJ, jf);
appG.openFile(jf);
stG = appG.state();
check('GUI: a .jfif file (a JPEG with an unusual extension, as saved by some browsers) can be opened', isequal(size(stG.orig), [40 50 3]));
delete(jf);  delete(tmpJ);
if exist(finalModel, 'file') && exist('plV', 'var')                     % Find ALL on a scene with one rendered plate: number above the plate, Result and SVM characters shown
    sceneG = 0.45 * ones(300, 420, 3) + 0.02 * rand(300, 420, 3);
    pg0 = imResize(plV, 150 / size(plV, 2), 'bilinear');
    if size(pg0, 3) == 1, pg0 = repmat(pg0, [1 1 3]); end
    sceneG(120:119 + size(pg0, 1), 130:129 + size(pg0, 2), :) = pg0;
    appG.loadImage(min(max(sceneG, 0), 1), 'scene with one plate');
    cbAll.Value = true;
    appG.recognizeAll();
    stG = appG.state();
    txtG = findall(appG.fig, 'Type', 'text');
    imgG = findall(appG.fig, 'Type', 'image');
    check('GUI Find ALL: the plate is read, its number is written above its box, "Result" and the gallery with the SVM characters are filled (not blank)', ...
          ~isempty(stG.plates) && ~isempty(stG.plates(1).chars) && ~isempty(stG.plates(1).segPlate) && ...
          any(arrayfun(@(t) contains(string(t.String), stG.plates(1).text), txtG)) && numel(imgG) >= 3);
    appG.showPlate(1);
end
close(appG.fig);

% ------------- consensus vote over filtered copies -------------
if exist(finalModel, 'file') && exist('plV', 'var')
    F5 = load(finalModel);
    txtC = consensusText(plV, [1 1 size(plV, 2) size(plV, 1)], 'ABC1234', F5.model);
    okOpt = true;
    try, recognizePlates(repmat(0.5, 60, 90, 3), F5.model, 'Consensus', true); catch, okOpt = false; end
    check('consensusText: a clean rendered plate keeps its reading (ABC1234); recognizePlates accepts the option "Consensus" (off by default)', strcmp(txtC, 'ABC1234') && okOpt);
end

% ------------- touching characters, lamp glare, plate-like regions that could not be read -------------
Gt = 0.1 * ones(100, 300);                                           % three bright blocks 40 x 60, 6 px apart, joined by thin necks
for q = 0:2, Gt(21:80, 20 + q * 46 + (1:40)) = 0.9; end
Gt(48:52, 61:66) = 0.9;  Gt(48:52, 107:112) = 0.9;
nNoSplit = numel(segmentChars(Gt, 'Polarity', 'bright'));
nSplit = numel(segmentChars(Gt, 'Polarity', 'bright', 'Split', true));
check('segmentChars: three touching characters are one wide blob without splitting and three characters with "Split"', nNoSplit < 3 && nSplit == 3);
Gm = 0.1 * ones(100, 260);                                           % six bright blocks, one of them 40 px wide (two characters that touch, joined by a thin neck)
for q = [20 50 130 160 190], Gm(21:80, q + (0:17)) = 0.9; end
Gm(21:80, 80:119) = 0.9;  Gm(21:44, 98:101) = 0.1;  Gm(57:80, 98:101) = 0.1;
check('segmentChars: option FixMerged cuts a block that is twice as wide as the others, with a deep valley, in two (7 instead of 6 characters), the default does not', ...
      numel(segmentChars(Gm, 'Polarity', 'bright')) == 6 && numel(segmentChars(Gm, 'Polarity', 'bright', 'FixMerged', true)) == 7);
Gnv = 0.04 * ones(120, 200, 3);  Gnv(60:90, 50:150, :) = 0.12;                % a dark photo: the night-vision copy is brighter, has the same size and stays in [0, 1]
Jnv = nightVision(Gnv + 0.01 * rand(size(Gnv)));
check('nightVision: same size, values in [0, 1], and a very dark photo becomes clearly brighter', ...
      isequal(size(Jnv), size(Gnv)) && min(Jnv(:)) >= 0 && max(Jnv(:)) <= 1 && mean(Jnv(:)) > 2 * mean(Gnv(:)));
check('segmentPlateBest: "Split" is a fallback (a normal plate gives the same characters with and without it)', ...
      exist(finalModel, 'file') == 0 || isequal(numel(nthOut(1, @segmentPlateBest, plV, 'Split', true)), numel(nthOut(1, @segmentPlateBest, plV, 'Split', false))));
if exist(finalModel, 'file')
    F4 = load(finalModel);
    [oU, uU] = recognizePlates(repmat(0.5 + 0.1 * rand(120, 200), [1 1 3]), F4.model);
    check('recognizePlates returns the plate-like regions that could not be read as a second output (struct array with box, score, width)', ...
          isstruct(uU) && all(ismember({'box', 'score', 'width'}, fieldnames(uU))) && isstruct(oU));
    scC = 0.45 * ones(300, 420, 3) + 0.02 * rand(300, 420, 3);              % one rendered plate on a plain scene: "Cars" cuts a car out around it
    pgC = imResize(plV, 150 / size(plV, 2), 'bilinear');  if size(pgC, 3) == 1, pgC = repmat(pgC, [1 1 3]); end
    scC(120:119 + size(pgC, 1), 130:129 + size(pgC, 2), :) = pgC;
    [oC, ~, cC] = recognizePlates(min(max(scC, 0), 1), F4.model, 'Cars', true);
    check('recognizePlates option "Cars": a third output lists the car regions (box, plate, source), the car of a plate that was read points to it, plates carry the characters the SVM saw', ...
          isstruct(cC) && all(ismember({'box', 'plate', 'source'}, fieldnames(cC))) && ~isempty(oC) && ~isempty(cC) && cC(1).plate == 1 && ...
          all(ismember({'chars', 'charBoxes', 'segPlate'}, fieldnames(oC))) && ~isempty(oC(1).chars));
    check('the character SVM of the final model uses signed HOG features (model.hog) and the older models still work without that field', ...
          isfield(F4.model, 'hog') && F4.model.hog.signed && size(F4.model.svm.SV, 2) == 648 && ~isfield(load(fullfile('models', 'lpr_svm_model.mat'), 'model').model, 'hog'));
    plS = imResize(plV, 90 / size(plV, 2), 'bilinear');                  % a plate only 90 px wide
    rB = recognizePlate(plS, F4.model, 'Plate', plS);
    rN = recognizePlate(plS, F4.model, 'Plate', plS, 'SmallBoost', 0);
    check('recognizePlate: SmallBoost (default 160 px: small plate crops are enlarged and sharpened) runs on a 90 px plate and can be switched off with 0', ...
          isstruct(rB) && isstruct(rN) && (rB.found || ~isempty(rB.reason)) && (rN.found || ~isempty(rN.reason)));
    rng(7);                                                              % a two-line plate (scooter) on a grey car body
    sty = find(~tpl.isTest, 1);
    rowA = renderPlate('KA 02 K', tpl, sty, 'Height', 100, 'Style', 'yellow');
    rowB = renderPlate('X 9181', tpl, sty, 'Height', 100, 'Style', 'yellow');
    wB = max(size(rowA, 2), size(rowB, 2));
    padRow = @(a) [a, repmat(a(:, end, :), [1, wB - size(a, 2), 1])];
    P2 = imResize([padRow(rowA); padRow(rowB)], 0.9, 'bilinear');
    sceneTL = 0.5 * ones(480, 640, 3) + 0.02 * randn(480, 640, 3);
    sceneTL(200:199 + size(P2, 1), 200:199 + size(P2, 2), :) = P2;
    outTL = recognizePlates(min(max(sceneTL, 0), 1), F4.model);
    check('recognizePlates: both rows of a two-line plate are found and joined (lines = 2)', ...
          any(arrayfun(@(o) o.lines == 2 && numel(strrep(o.text, ' ', '')) >= 8, outTL)));
    outTL1 = recognizePlates(min(max(sceneTL, 0), 1), F4.model, 'TwoLine', false);
    check('recognizePlates: TwoLine false never joins rows', all(arrayfun(@(o) o.lines == 1, outTL1)));
end


% -------------------------------- summary ------------------------------------
passed = sum([results{:, 2}]);
fprintf('\n%d of %d checks passed.\n', passed, size(results, 1));
if passed < size(results, 1), error('run_tests:failed', '%d check(s) failed.', size(results, 1) - passed); end

    function check(name, cond)
        results(end+1, :) = {name, logical(cond)};
        fprintf('%s  %s\n', ternary(cond, 'PASS', 'FAIL'), name);
    end
end

% ============================== local helpers ================================
function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function p = imageMetricsPsnr(a, b)
[~, p] = imageMetrics(a, b);
end

function v = nthOut(n, f, varargin)
% the n-th output of a function call
out = cell(1, n);
[out{:}] = f(varargin{:});
v = out{n};
end

function t = throwsError(f)
% true if calling f raises an error
try, f(); t = false; catch, t = true; end %#ok<NOCOM,CTCH>
end

function c = sparseCoef(m, n)
% coefficient vector of length n (one entry per training sample used for the SVs)
c = zeros(n, 1);  c(m.idx) = m.coef;
end

function v = bboxIou(a, b)
x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
x2 = min(a(1)+a(3), b(1)+b(3));  y2 = min(a(2)+a(4), b(2)+b(4));
inter = max(0, x2-x1) * max(0, y2-y1);
v = inter / (a(3)*a(4) + b(3)*b(4) - inter);
end

function n = floodCount(bw)
% reference component count by explicit flood fill (8-connectivity)
seen = false(size(bw));  n = 0;
[h, w] = size(bw);
for r = 1:h
    for c = 1:w
        if bw(r, c) && ~seen(r, c)
            n = n + 1;  stack = [r c];  seen(r, c) = true;
            while ~isempty(stack)
                p = stack(end, :);  stack(end, :) = [];
                for dr = -1:1
                    for dc = -1:1
                        q = p + [dr dc];
                        if all(q >= 1 & q <= [h w]) && bw(q(1), q(2)) && ~seen(q(1), q(2))
                            seen(q(1), q(2)) = true;  stack(end+1, :) = q; %#ok<AGROW>
                        end
                    end
                end
            end
        end
    end
end
end
