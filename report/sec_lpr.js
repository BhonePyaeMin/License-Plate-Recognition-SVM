'use strict';
// Chapter 6: SVM and licence plate recognition.
const L = require('./lib');
const { M, f0, f1, f2, pct } = L;
const r = (...parts) => parts.map((p) => (typeof p === 'string' ? M.r(p) : p));
const P = (x, dgt = 1) => (100 * Number(x)).toFixed(dgt);

module.exports = function lpr(b, d) {
  const p = d.pipeline;
  const s = d.svm;
  const ev = p.eval;
  const mid = ev[1];
  const fn = d.code.modules.svm;
  const fl = d.code.modules.lpr;

  b.h1('License Plate Recognition with an SVM');
  b.p('This chapter applies the three modules to the project topic. It describes the recogniser stage by stage, explains the support vector machine, documents how the training data were produced and presents the training experiments, the end-to-end evaluation on synthetic scenes, an analysis of the errors and, in the last section, the evaluation on real photographs.');

  // ================================================================== 6.1 overview
  b.h2('Problem statement and overview');
  b.p(`The input is a colour or gray-scale photograph that contains one roughly frontal licence plate with dark characters on a light background. The output is the plate text, the plate position and a confidence per character. Two SVMs take part: a __plate / not-plate SVM__ that ranks the candidate regions of the photo (${b.ref('sec:detect')}) and a __character SVM__ with 36 classes that reads the characters of the chosen region (${b.ref('sec:svm')}). ${b.ref('fig:pipeline')} showed the data flow; ${b.ref('fig:stages')} shows every intermediate result for one synthetic test image, as produced by <<showPipeline>>.`);
  b.figure('pipeline_stages.png', `The recogniser on one synthetic test scene (true plate ${p.example.truth}, read ${p.example.read}, font ${p.example.font}, a font held out from training).`, { key: 'fig:stages', width: 610 });

  // ================================================================== 6.2 detection
  b.h2('Plate detection', { key: 'sec:detect' });
  const ra = d.real ? d.real.ablation[0] : null;
  b.p(`<<detectPlate>> works in two stages: it __proposes__ candidate regions with image processing (Modules 1–3) and then __ranks__ them. The first version of the detector used one method at one scale and was developed on synthetic scenes, where it found the plates. On the 49 real photographs, a simplified single-scale edge detector (configuration A in ${b.ref('tab:realablation')}) reads only ${ra ? ra.dev.exact + ra.test.exact : '??'} plates exactly. The final detector therefore uses several scales, a second proposal method and an SVM for the ranking (${b.ref('sec:real')}).`);
  b.h3('Proposing candidate regions');
  b.p('Two methods propose regions; their results are pooled and overlapping boxes (intersection over union above 0.4) are merged, keeping the one with the higher score.');
  b.numbered([
    '**Vertical-edge blobs** (repeated at the working widths 640, 960 and 1440 pixels, as far as the photo has that many): resize with bilinear interpolation (Module 3); contrast stretch between the 1 % and 99 % percentiles and a 5 × 5 Gaussian filter with σ = 1 (Module 1); absolute horizontal Sobel response, normalised to [0, 1] and thresholded with the larger of Otsu’s level and 0.06; a morphological closing with a 3 × 45 pixel rectangle joins the strokes of neighbouring characters, also across the gap between groups such as “ABC” and “1234”, an opening with a 6 × 13 rectangle removes thin clutter and holes are filled (Module 2). Connected components with a bounding-box aspect ratio between 2 and 13 (the blob covers only the text row), at least 8 × 45 pixels and an extent of at least 0.45 become candidates, scored by edge density × Otsu separability of the gray values × preference for an aspect ratio near 6 × a colour factor 0.3 + (fraction of white or yellow pixels). The box is enlarged by 6 % of its width and 35 % of its height to include the plate border.',
    '**Rows of character-sized blobs** (at 960 and 1440 pixels): the photo is binarised with the local adaptive threshold (Module 2), for dark and for bright foreground; connected components of 10–90 pixels height, not wider than 1.4 times their height, that do not touch the border are kept; two blobs are linked when they have similar heights, lie on one line and are at most two heights apart; every group of 4 to 14 linked blobs becomes a candidate box. This method was added because photographs of cars contain many structures with vertical edges (grilles, lamps), which swamp the edge method, whereas a row of similar characters is rare.',
  ]);
  b.h3('Ranking: the plate SVM');
  b.p('The candidates of one photo are ranked by a second SVM. For every candidate region the crop is resized to 32 × 128 pixels, its contrast is stretched, and a HOG descriptor with 8 × 8 cells and 9 orientations (1620 values) is computed (<<plateFeatures>>). A binary RBF-SVM (<<trainPlateModel>>, the same SMO trainer as for the characters) gives a decision value, positive for plate-like regions (<<plateScore>>). The final score of a candidate is its SVM decision value plus 0.5 times a character-row check: the five best candidates of the SVM are cropped, segmented into characters (Section 6.3), and rewarded for 3–12 characters of similar height on a line with regular spacing that fill a sensible part of the crop. The candidate with the highest score is the plate. Without a plate SVM (for example before it is trained) the row check and the candidate score rank the regions.');
  b.p(`Training data of the plate SVM are the candidate regions that the detector produces on the real “dev” photographs (${b.ref('sec:real')}). A region counts as a plate when the character SVM reads at least 40 % of its characters correctly (edit distance against the known plate text), otherwise as a non-plate. Positives are augmented with 6 randomly shifted and scaled crops each and with 200 synthetic plates (<<renderPlate>>), and random background patches are added as negatives.`);
  const sw = d.sweep;
  if (sw) {
    b.p(`The width of the closing was the only parameter of the edge method that needed tuning. This experiment was done with the first, single-scale edge detector without verification, on synthetic scenes. ${b.ref('tab:sweepdet')} shows the detection rate for several widths on ${sw.detect.n} synthetic scenes of difficulty 0.6 with unseen fonts: a closing that is too narrow cannot bridge the gap between character groups and the detector boxes only half of the plate, a closing that is too wide merges the plate with neighbouring structures.`);
    b.table(
      [{ h: 'Closing width (fraction of image width)', w: 3.4 }, { h: 'Plate found (IoU > 0.5)', w: 2.2, a: 'r' }, { h: 'Plate fully inside the box', w: 2.4, a: 'r' }, { h: 'No candidate', w: 1.6, a: 'r' }, { h: 'Mean IoU', w: 1.2, a: 'r' }],
      sw.detect.closeWidth.map((w, i) => {
        const best = w === 0.07;
        const o = (t) => (best ? { t, b: true } : t);
        return [o(f2(w) + (best ? ' (chosen)' : '')), o(`${sw.detect.iou50[i]} / ${sw.detect.n}`), o(`${sw.detect.covered95[i]} / ${sw.detect.n}`), o(String(sw.detect.none[i])), o(f2(sw.detect.meanIoU[i]))];
      }),
      'Effect of the closing width on plate detection (development experiment).', { key: 'tab:sweepdet' });
  }

  // ================================================================== 6.3 segmentation
  b.h2('Character segmentation', { key: 'sec:segment' });
  b.p('<<segmentChars>> turns the plate crop into a list of normalised character images:');
  b.numbered([
    'The plate is resized to a height of 100 pixels with bilinear interpolation. A 3 × 3 Gaussian smoothing is available but switched off by default: on the real photographs, where plates are small and already blurry, it lowered the character accuracy, and it cost a little accuracy on the synthetic scenes as well (last row of the table below).',
    'It is binarised with Otsu’s threshold. Both polarities (dark characters, bright characters) are tried and the one that produces the larger group of characters is kept.',
    'The foreground is labelled with 8-connectivity (<<labelComponents>>) and components are discarded when they touch the image border, are lower than 25 % or higher than 95 % of the plate height, or are wider than 1.5 times their height.',
    '**Grouping:** the characters of a plate have similar heights and lie on one line. For every remaining component, the components whose height is between 0.65 and 1.6 times its height are collected, a line is fitted through their centroids (every pair of components proposes a line; a component is an inlier when it lies within 0.30 character heights of the line and the line is flatter than 25°), and the largest group wins.',
    '**De-skew:** if the fitted line is tilted by 1° or more, the plate is rotated by the opposite angle (Module 3, reverse mapping with bilinear interpolation, border colour as fill) and steps 2–4 are repeated.',
    '**Normalise:** every character is cut out with only its own connected component as mask, cropped to its bounding box, scaled with its aspect ratio preserved so that its longer side is 80 % of a 32 × 32 canvas, and centred. The same function (<<normalizeChar>>) is used for training characters, so training and recognition see identical geometry.',
  ]);
  if (sw && sw.seg) {
    b.p(`Variants were compared on ${sw.segN} synthetic scenes (difficulty 0.5, unseen fonts, SVM trained on other fonts) with the first, single-scale detector (${b.ref('tab:sweepseg')}). Adding a local adaptive threshold as a second binarisation candidate was expected to help against uneven lighting, but it lowered the accuracy, so the default is Otsu only; widening the accepted height range (for characters such as Q with a long tail) made no difference on this data and was kept because it is harmless. Switching the smoothing off (last row) cost a few points on these synthetic scenes; it was chosen because it helped on the real photographs, which is the purpose of the system (${b.ref('sec:real')}). The same real-photo data were also used to choose it, so this choice is itself a (small) tuning step on the dev photographs.`);
    b.table(
      [{ h: 'Configuration', w: 3.8 }, { h: 'Correct character count', w: 2, a: 'r' }, { h: 'Exact plate (no layout)', w: 2, a: 'r' }, { h: 'Exact plate (layout known)', w: 2.2, a: 'r' }],
      sw.seg.map((c) => { const bold = c.name.includes('(default)'); const o = (t) => (bold ? { t, b: true } : t); return [o(c.name), o(P(c.countOk) + ' %'), o(P(c.exactNoFormat) + ' %'), o(P(c.exactFormat) + ' %')]; }),
      'Segmentation variants compared on the same scenes (development experiment).', { key: 'tab:sweepseg' });
  }

  // ================================================================== 6.4 HOG
  b.h2('Feature extraction: HOG', { key: 'sec:hog' });
  b.p('A raw 32 × 32 image has 1024 values that change a lot with the font, whereas the arrangement of stroke directions is much more stable. The histogram of oriented gradients (Dalal and Triggs) describes exactly this. <<hogFeatures>> computes:');
  b.numbered([
    'central-difference gradients G_x, G_y (kernel [−1 0 1]) and the magnitude and the unsigned orientation (0–180°) of every pixel;',
    'for every 8 × 8 pixel cell (4 × 4 cells), a histogram of 9 orientation bins in which each pixel votes with its gradient magnitude, split linearly between the two nearest bins;',
    'overlapping blocks of 2 × 2 cells (stride one cell, 3 × 3 blocks) whose 36 values are normalised with the L2-Hys scheme: v ← v/√(‖v‖² + ε), clip at 0.2, normalise again, which makes the descriptor robust to contrast changes.',
  ]);
  b.p('The descriptor has 3 × 3 × 36 = 324 values per character.');

  // ================================================================== 6.5 SVM theory
  b.h2('Support vector machine classifier', { key: 'sec:svm' });
  b.h3('Binary soft-margin SVM');
  b.p('Given training vectors x_i with labels y_i ∈ {+1, −1}, a support vector machine looks for the separating hyperplane with the largest margin. Allowing a few violations ξ_i of the margin (soft margin) leads to the primal problem');
  b.eq(r(M.lim(r('min'), r('w, b, ξ')), M.frac(r('1'), r('2')), M.sup(r('‖', 'w', '‖'), '2'), '+', 'C', M.sum(M.sub('ξ', 'i'), 'i'), '          s.t.  ', M.sub('y', 'i'), M.rb(r(M.sup('w', 'ᵀ'), 'φ', M.rb(M.sub('x', 'i')), '+', 'b')), '≥', '1', '−', M.sub('ξ', 'i'), ',  ', M.sub('ξ', 'i'), '≥', '0'));
  b.p('where the constant C trades margin width against violations. Through its Lagrangian dual the problem only needs inner products of the mapped points, which are replaced by a kernel function K(x_i, x_j) = φ(x_i)·φ(x_j) (the “kernel trick”):');
  b.eq(r(M.lim(r('max'), r('α')), M.sum(M.sub('α', 'i'), 'i'), '−', M.frac(r('1'), r('2')), M.sum(M.sum(r(M.sub('α', 'i'), M.sub('α', 'j'), M.sub('y', 'i'), M.sub('y', 'j'), 'K', M.rb(r(M.sub('x', 'i'), ',', M.sub('x', 'j')))), 'j'), 'i'), '          s.t.  ', '0', '≤', M.sub('α', 'i'), '≤', 'C', ',  ', M.sum(r(M.sub('α', 'i'), M.sub('y', 'i')), 'i'), '=', '0'), 'eq:dual');
  b.p(`The training points with α_i > 0 are the __support vectors__; the classifier is f(x) = Σ α_i y_i K(x_i, x) + b and the predicted class is the sign of f. We use the radial basis function (RBF) kernel, which measures similarity by distance and lets the boundary curve around classes (${b.ref('fig:toy')} below shows the effect on a toy problem):`);
  b.eq(r('K', M.rb(r('x', ',', 'x′')), '=', M.sup('e', r('−', 'γ', M.sup(r('‖', 'x', '−', 'x′', '‖'), '2')))));
  b.figure('svm_toy.png', `A linear and an RBF kernel on two concentric rings. The linear SVM reaches ${P(s.toy.linear.accuracy, 0)} % on held-out points, the RBF SVM ${P(s.toy.rbf.accuracy, 0)} %. Circled points are support vectors.`, { key: 'fig:toy', width: 560 });

  b.h3('Training with sequential minimal optimisation (SMO)');
  b.p('The dual problem is a quadratic programme with one equality constraint. SMO (Platt, 1998) solves it by repeatedly optimising two multipliers α_i and α_j analytically while all others stay fixed, which keeps the constraint Σ α_i y_i = 0 satisfied. With the prediction errors E = f(x) − y the update of the second multiplier is');
  b.eq(r(M.sup(M.sub('α', 'j'), 'new'), '=', M.sub('α', 'j'), '+', M.frac(r(M.sub('y', 'j'), M.rb(r(M.sub('E', 'i'), '−', M.sub('E', 'j')))), r('η')), ',   ', 'η', '=', M.sub('K', 'ii'), '+', M.sub('K', 'jj'), '−', '2', M.sub('K', 'ij')));
  b.p('The result is clipped to the interval [L, H] that the box constraint 0 ≤ α ≤ C and the equality constraint allow, and α_i is adjusted by y_i y_j (α_j − α_j^{new}). The pair is chosen with the maximal-violating-pair rule and the second-order criterion of Fan, Chen and Lin: i is the point that violates the optimality (KKT) conditions most, and j is the partner that promises the largest decrease of the objective. Training stops when the largest violation is below 10⁻³. The bias is the mean of −(error) over the free support vectors (0 < α < C). <<svmTrainBinary>> keeps the full kernel matrix of the (small) pair problem in memory and updates the error vector with two columns of it per iteration.');

  b.h3('Multi-class classification');
  b.p('The 36 characters are separated by the __one-vs-one__ scheme: one binary SVM is trained for each pair of classes, K(K − 1)/2 = 630 machines, each on the examples of its two classes only. This keeps every optimisation problem small (here about 500 samples) and is usually faster than one-vs-rest, whose problems contain all samples. A new character is classified by letting every machine vote for one of its two classes; the class with the most votes wins and ties are broken by the sum of the decision values. The share of the 35 duels that the winner won is reported as a confidence. The support vectors of all machines are stored once and shared (<<svmTrain>>, <<svmPredict>>), so a prediction needs one kernel matrix between the test vectors and the shared support vectors.');
  b.table(
    [{ h: 'Function', w: 3.8 }, { h: 'Purpose', w: 5.2 }],
    fn.concat(fl).map((f) => [`<<${f.signature}>>`, f.description]),
    'Functions of the SVM (toolbox/svm) and of the licence plate recogniser (toolbox/lpr).', { key: 'tab:svmfuncs', size: 17 });

  // ================================================================== 6.6 data
  b.h2('Training data', { key: 'sec:data' });
  b.p(`The character SVM needs examples of all 36 characters, in many fonts, sizes and degradations. The 49 real photographs that the project collected (${b.ref('sec:real')}) contain only a few hundred characters and not all classes, so the bulk of the training data is generated: characters are rendered from fonts and degraded with the toolbox. This section describes the synthetic data; ${b.ref('sec:real')} describes how real characters cut from the photographs are added in a second step. The synthetic-only model is the baseline, and its accuracy on real photographs is measured in ${b.ref('sec:real')}.`);
  b.h3('Glyph rendering');
  b.p(`<<buildGlyphTemplates>> draws the 36 characters in every font found on the computer (${s.data.trainFonts + s.data.testFonts} font variants, regular and bold) into a hidden MATLAB figure as a 6 × 6 mosaic, captures the pixels with <<getframe>> and cuts each glyph out (${b.ref('fig:glyphs')}). The result is cached because rendering takes about 15 seconds.`);
  b.figure('glyph_montage.png', 'The rendered glyphs: one row per font variant, 36 characters per row.', { key: 'fig:glyphs', width: 610 });
  b.h3('Degradation');
  b.p(`<<augmentGlyph>> turns a clean glyph into a training sample that resembles a character cut from a photographed plate: random height of 20–60 pixels, random horizontal scaling by 0.7–1.3 (condensed to wide typefaces, added after the first real-photo tests), random shear (±0.18) and rotation (±8°) with Module 3, random ink and paper brightness, an optional down- and up-scaling (low resolution), Gaussian blur (σ = 0.3–1.4 pixels) and noise (up to 0.07), followed by Otsu binarisation with a random offset of ±0.06 of the threshold level (which varies the stroke weight), removal of specks and the same normalisation that the recogniser uses. ${b.ref('fig:samples')} shows examples; each column is one class and each row a different random degradation.`);
  b.figure('char_samples.png', 'Training samples after degradation and normalisation (3 per class; 0–9 then A–Z).', { key: 'fig:samples', width: 610 });
  b.h3('Training and test sets');
  b.p(`The fonts are split: ${s.data.trainFonts} fonts are used for training and ${s.data.testFonts} fonts (Verdana Bold, Calibri Bold, Trebuchet MS Bold and Courier New Bold) are held out and never seen by the SVM. This tests whether the classifier learned the shapes of the characters rather than the shapes of particular fonts. The training set has ${s.data.trainSamples.toLocaleString('en-US')} images (250 per class). Two test sets are generated with other random seeds: ${s.data.unseenFontSamples.toLocaleString('en-US')} images in the unseen fonts and ${s.data.seenFontSamples} new images in the training fonts.`);
  b.h3('Synthetic test scenes');
  b.p('The end-to-end tests use whole scenes created by <<makeScene>>: a gradient background with rectangles as buildings, a road, a car with windshield, headlights, grille and bumper, and a plate that is rendered by <<renderPlate>> (white or yellow, with a border and a random font and spacing). The plate is scaled to 150–260 pixels width, warped into the scene by rotation and shear with Module 3, and the whole image receives uneven lighting, blur and noise. A difficulty parameter h ∈ [0, 1] scales these disturbances:');
  b.table(
    [{ h: 'Disturbance', w: 3.2 }, { h: 'Range', w: 3.6 }, { h: 'h = 0.2', w: 1.2, a: 'r' }, { h: 'h = 0.5', w: 1.2, a: 'r' }, { h: 'h = 0.8', w: 1.2, a: 'r' }],
    [
      ['Plate rotation', 'uniform in ±(2 + 8h) degrees', '±3.6°', '±6.0°', '±8.4°'],
      ['Plate shear', 'uniform in ±0.1 h', '±0.02', '±0.05', '±0.08'],
      ['Brightness gain', '1 − 0.45 h · u, u uniform in [0, 1]', '≥ 0.91', '≥ 0.78', '≥ 0.64'],
      ['Camera blur (σ, pixels)', '0.3 + h · u', '≤ 0.5', '≤ 0.8', '≤ 1.1'],
      ['Noise (σ)', '0.005 + 0.03 h · u', '≤ 0.011', '≤ 0.020', '≤ 0.029'],
    ], 'Disturbances of the synthetic scenes as a function of the difficulty h.', { key: 'tab:difficulty' });

  // ================================================================== 6.7 training experiments
  b.h2('Training and model selection', { key: 'sec:training' });
  const c = s.curve;
  b.p(`${b.ref('fig:curves')} (left) and ${b.ref('tab:curve')} show how the accuracy depends on the number of training images per class. The accuracy on unseen fonts rises from ${P(c.unseen[0])} % with 10 images per class to ${P(c.unseen[4])} % with 250, with diminishing returns beyond 50. Fonts seen in training score higher (${P(c.seen[4])} % at 250 images), the difference of about one percentage point is the price of the unseen fonts.`);
  b.figure('svm_curves.png', 'Left: learning curve of the RBF-SVM. Right: accuracy on the unseen fonts (%) for a grid of C and γ.', { key: 'fig:curves', width: 600 });
  b.table(
    [{ h: 'Images per class', w: 1.6, a: 'r' }, { h: 'Accuracy, unseen fonts', w: 2, a: 'r' }, { h: 'Accuracy, seen fonts', w: 2, a: 'r' }, { h: 'Support vectors', w: 1.6, a: 'r' }, { h: 'Training time (s)', w: 1.6, a: 'r' }],
    c.n.map((n, i) => [String(n), P(c.unseen[i]) + ' %', P(c.seen[i]) + ' %', String(c.supportVectors[i]), f1(c.trainSeconds[i])]),
    'Learning curve (C = 10, RBF kernel with γ = 1/(d · var(X))).', { key: 'tab:curve' });
  const k = s.kernel;
  b.p(`Three kernels were compared on the full training set (${b.ref('tab:kernel')}). The differences are small. With ${s.data.unseenFontSamples.toLocaleString('en-US')} test images the standard error of an accuracy near 97 % is about 0.4 percentage points, so the 0.5-point advantage of the RBF kernel over the linear kernel is within the sampling error. The HOG feature space is already almost linearly separable for this task. We keep the RBF kernel as the default because it gave the highest accuracy and is the standard choice, but a linear SVM would be nearly as accurate with fewer support vectors (${k.linear.supportVectors} against ${k.rbf.supportVectors}), a point to remember when speed matters.`);
  b.table(
    [{ h: 'Kernel', w: 2.4 }, { h: 'Unseen fonts', w: 1.6, a: 'r' }, { h: 'Seen fonts', w: 1.6, a: 'r' }, { h: 'Support vectors', w: 1.8, a: 'r' }, { h: 'Training time (s)', w: 1.8, a: 'r' }],
    [['Linear', k.linear], ['RBF (default)', k.rbf], ['Polynomial, degree 3', k.poly]].map(([n, v]) => [n, P(v.unseenAccuracy) + ' %', P(v.seenAccuracy) + ' %', String(v.supportVectors), f1(v.trainSeconds)]),
    'Kernel comparison (C = 10, 250 images per class).', { key: 'tab:kernel' });
  const gr = s.grid;
  const flat = [].concat(...gr.accuracy);
  b.p(`The grid over C ∈ {${gr.C.join(', ')}} and γ ∈ {${gr.gammaFactor.join(', ')}} times the default (right panel of ${b.ref('fig:curves')}) is nearly flat: all nine combinations lie between ${P(Math.min(...flat))} % and ${P(Math.max(...flat))} %. The classifier is therefore not sensitive to these hyper-parameters, and the defaults C = 10 and γ = 1/(d · var(X)) = ${f2(s.model.gamma)} were kept. The final model has ${s.model.binaryMachines} binary machines that share ${s.model.sharedSupportVectors.toLocaleString('en-US')} support vectors and trains in a few seconds.`);

  // ================================================================== 6.8 evaluation
  b.h2('End-to-end evaluation', { key: 'sec:eval' });
  b.p(`The complete recogniser was evaluated with <<evaluateLPR>> on ${mid.N} new synthetic scenes for each of three difficulty levels. The scenes use the four held-out fonts and the SVM was trained without them, so neither the fonts nor the scenes were seen during development of the classifier. Each scene is read twice: once with the plain 36-class decision and once with the letter/digit layout of the plate given (for example “LLL DDDD”), in which case the SVM decision of a character is restricted to digits or to letters. ${b.ref('tab:eval')} gives the results.`);
  b.table(
    [{ h: 'Measure', w: 4 }, ...ev.map((e) => ({ h: `h = ${e.hard}`, w: 1.5, a: 'r' }))],
    [
      ['Plate located (IoU > 0.5)', ...ev.map((e) => P(e.detectionRate) + ' %')],
      ['Correct number of characters', ...ev.map((e) => P(e.segmentationRate) + ' %')],
      ['Character accuracy, no layout', ...ev.map((e) => P(e.charAccuracyNoFormat) + ' %')],
      ['Character accuracy, layout known', ...ev.map((e) => P(e.charAccuracyWithFormat) + ' %')],
      [{ t: 'Exact plate, no layout', b: true }, ...ev.map((e) => ({ t: P(e.plateAccuracyNoFormat) + ' %', b: true }))],
      [{ t: 'Exact plate, layout known', b: true }, ...ev.map((e) => ({ t: P(e.plateAccuracyWithFormat) + ' %', b: true }))],
      ['Time per image', ...ev.map((e) => f2(e.secondsPerImage) + ' s')],
    ], `End-to-end results on ${mid.N} synthetic scenes per difficulty level (unseen fonts). Character accuracy is 1 − (edit distance / plate length), averaged.`, { key: 'tab:eval' });
  b.p(`Detection is almost perfect at every level. The accuracy falls steadily with difficulty because the segmentation fails more often (${P(ev[0].segmentationRate, 0)} % to ${P(ev[2].segmentationRate, 0)} % correct character counts) and the characters become harder to classify. Knowing the layout improves the exact-plate rate by ${f0(100 * (ev[0].plateAccuracyWithFormat - ev[0].plateAccuracyNoFormat))} to ${f0(100 * (ev[2].plateAccuracyWithFormat - ev[2].plateAccuracyNoFormat))} percentage points. ${b.ref('fig:eval')} shows the first twelve scenes of the medium level.`);
  b.figure('eval_examples.png', 'First twelve scenes of the medium difficulty level. Titles show the true plate and the SVM reading (green: correct, red: wrong); the red box is the detected plate.', { key: 'fig:eval', width: 610 });
  const t = p.timing;
  b.p(`**Speed.** ${b.ref('tab:timing')} breaks the time per image down by stage (mean of ${p.errorsN} scenes). Detection dominates; extracting the HOG features and classifying all characters of a plate together take only about ${f0(t.classifyMs)} ms.`);
  b.table(
    [{ h: 'Stage', w: 3 }, { h: 'Mean time (ms)', w: 2, a: 'r' }],
    [['Plate detection (640 × 480 image)', f0(t.detectMs)], ['Character segmentation', f0(t.segmentMs)], ['HOG and SVM classification', f0(t.classifyMs)], [{ t: 'Total', b: true }, { t: f0(t.detectMs + t.segmentMs + t.classifyMs), b: true }]],
    'Computation time per stage.', { key: 'tab:timing' });

  // ================================================================== 6.9 error analysis
  b.h2('Error analysis', { key: 'sec:errors' });
  b.h3('Single-character errors');
  const tc = s.topConfusions;
  b.p(`${b.ref('fig:confusion')} is the confusion matrix of the SVM on the ${s.data.unseenFontSamples.toLocaleString('en-US')} test characters of the unseen fonts (overall accuracy ${P(s.confusionOverallAccuracy)} %). Almost all mass lies on the diagonal. The most frequent confusions are ${tc.slice(0, 5).map((x) => `${x.truth}→${x.read} (${x.count} of ${x.of})`).join(', ')}. They are pairs of characters that share their main strokes (E/B/F, T/W, 0/O); we did not analyse the causes further.`);
  b.figure('svm_confusion.png', 'Confusion matrix of the SVM on four unseen fonts (rows normalised).', { key: 'fig:confusion', width: 470 });

  b.h3('Plate-level errors');
  const e = p.errors;
  const N = p.errorsN;
  b.p(`To see why whole plates fail, ${N} further scenes of medium difficulty were read without a layout hint and every failure was assigned to one cause (${b.ref('tab:errors')}). A failure is a __look-alike confusion__ if all wrong characters belong to a pair that is visually almost identical (O/0, I/1, B/8, S/5, Z/2, D/0, Q/0, G/6, Q/O, D/O, U/V, I/L, G/0, C/G).`);
  b.table(
    [{ h: 'Outcome', w: 4.4 }, { h: 'Scenes', w: 1.2, a: 'r' }, { h: 'Share', w: 1.2, a: 'r' }],
    [
      ['Plate read exactly', e.correct],
      ['Look-alike confusion only (O/0, I/1, B/8, …)', e.lookalike],
      ['Other character substitution', e.otherSubstitution],
      ['Wrong number of characters (segmentation)', e.wrongCount],
      ['Box found but not on the plate', e.wrongRegion],
      ['No plate candidate', e.notFound],
    ].map(([n, v]) => [n, String(v), P(v / N) + ' %']),
    `Outcome of ${N} scenes at difficulty 0.5, no layout hint.`, { key: 'tab:errors' });
  const wrongTotal = N - e.correct;
  b.p(`Of the ${wrongTotal} failures, ${e.lookalike} (${P(e.lookalike / Math.max(wrongTotal, 1), 0)} %) are look-alike confusions, which the layout hint removes in the cases where the confused characters belong to different types (letter versus digit); ${e.wrongCount} (${P(e.wrongCount / Math.max(wrongTotal, 1), 0)} %) are segmentation errors. ${b.ref('fig:failures')} shows plate crops of failed cases. The crops shown there are character substitutions. The segmentation errors that were examined during development (not shown) were characters that merged with the plate frame after strong rotation and characters with a long tail (Q) that were lost.`);
  b.figure('failure_cases.png', 'Plate crops of failed scenes (true text, SVM reading, failure type).', { key: 'fig:failures', width: 610 });
  b.table(
    [{ h: 'Font (held out from training)', w: 4.4 }, { h: 'Scenes', w: 1.2, a: 'r' }, { h: 'Exact plate, no layout', w: 2.2, a: 'r' }],
    p.perFont.map((x) => [x.font, String(x.n), P(x.exactNoLayout) + ' %']),
    'Exact-plate rate per font in the error-analysis scenes. The counts per font are small (about 40), so differences of ten points are not significant.', { key: 'tab:perfont' });

  b.callout('What the synthetic evaluation does not show',
    `All scenes in this section are synthetic and were generated by code that the authors wrote, so they share assumptions with the recogniser (a roughly frontal plate, a clean rectangular frame, no glare, no dirt, no motion blur, no perspective foreshortening). The numbers above are a regression test and a way to find weaknesses, not an estimate of accuracy on photographs. The measurements on real photographs are in ${b.ref('sec:real')}, and they are much lower.`, 'warn');

  if (d.real) require('./sec_real')(b, d);
};
