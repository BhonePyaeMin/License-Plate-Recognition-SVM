'use strict';
// Results and discussion of Chapter 4 (Module 2).
const L = require('./lib');
const { f0, f1, f2, pct } = L;

module.exports = function m2results(b, d, { m }) {
  b.h2('Results', { key: 'sec:m2results' });

  // ------------------------------------------------------------------ edges
  b.h3('Edge detection');
  b.p(`${b.ref('fig:m2edges')} compares the three detectors on the synthetic scene (output of <<compareEdgeDetectors>>). To measure them, a test image with three shapes of known outline was corrupted with Gaussian noise of two strengths and each detector was run with its automatic threshold (Sobel and Prewitt: Otsu on the gradient magnitude; Canny: the defaults of ${b.ref('sec:m2theory')}). A detected pixel counts as correct when it lies within 2 pixels of the true outline, and an outline pixel counts as found when a detected pixel lies within 2 pixels. ${b.ref('fig:m2edgeeval')} shows the results and ${b.ref('tab:m2edge')} gives precision, recall and the F1 score.`);
  b.figure('m2_edges.png', 'Sobel, Prewitt and Canny on the synthetic scene: gradient magnitudes (top) and edge maps (bottom).', { key: 'fig:m2edges', width: 610 });
  b.figure('m2_edge_eval.png', 'Edge detectors on shapes with known outlines at two noise levels (standard deviation 0.02 and 0.08).', { key: 'fig:m2edgeeval', width: 610 });
  const e = m.edge;
  const row = (name, k) => [name, ...[0, 1].flatMap((i) => [f2(e[k][i].precision), f2(e[k][i].recall), { t: f2(e[k][i].f1), b: true }])];
  b.table(
    [{ h: 'Detector', w: 1.6 }, { h: `P (σ = ${e.sigmas[0]})`, w: 1.2, a: 'r' }, { h: 'R', w: 0.9, a: 'r' }, { h: 'F1', w: 0.9, a: 'r' }, { h: `P (σ = ${e.sigmas[1]})`, w: 1.2, a: 'r' }, { h: 'R', w: 0.9, a: 'r' }, { h: 'F1', w: 0.9, a: 'r' }],
    [row('Sobel', 'sobel'), row('Prewitt', 'prewitt'), row('Canny', 'canny')],
    'Precision (P), recall (R) and F1 score of the edge detectors on the shape test image.', { key: 'tab:m2edge' });
  b.p(`Computation time for the Canny detector on a 640 × 480 image was ${f0(m.timing.cannyMs)} ms; labelling its ${m.timing.edgePixels.toLocaleString('en-US')} edge pixels took ${f1(m.timing.labelMs)} ms.`);

  // ------------------------------------------------------------------ segmentation
  b.h3('Thresholding, region growing and colour');
  b.p(`${b.ref('fig:m2seg')} shows the segmentation techniques on the synthetic scene (output of <<compareSegmentation>>): Otsu and adaptive thresholds, region growing from the image centre, colour segmentation for white, Canny edges, edges closed and filled, and the result of shape cleaning.`);
  b.figure('m2_segmentation.png', 'Segmentation techniques on the synthetic scene.', { key: 'fig:m2seg', width: 610 });
  b.p(`For a quantitative comparison, eight small objects (24–34 pixels) were placed on a dark background under a lighting gradient that darkens the image to 30 % on the left and brightens it to 120 % on the right, with Gaussian noise of 0.03. Every method received the same Gaussian-smoothed image. ${b.ref('fig:m2segeval')} and ${b.ref('tab:m2seg')} give the Dice coefficient against the ground truth.`);
  b.figure('m2_seg_eval.png', 'Global, adaptive and region-growing segmentation under uneven lighting.', { key: 'fig:m2segeval', width: 610 });
  b.table(
    [{ h: 'Method', w: 5 }, { h: 'Dice coefficient', w: 2, a: 'r' }],
    [
      [`Global Otsu threshold (t = ${f2(m.seg.otsuLevel)})`, f2(m.seg.otsuDice)],
      ['Adaptive threshold (41 × 41 window, offset 0.03)', { t: f2(m.seg.adaptiveDice), b: true }],
      ['Region growing from one seed (tolerance 0.10), measured on that object only', f2(m.seg.regionDice)],
    ], 'Segmentation quality under uneven lighting.', { key: 'tab:m2seg' });
  b.p(`Region growing was also applied to the licence plate itself: a seed on the white plate background was grown with three tolerances (${b.ref('fig:m2region')}). The segmented area was ${pct(m.region.fraction[0])}, ${pct(m.region.fraction[1])} and ${pct(m.region.fraction[2])} of the image for tolerances ${m.region.tolerances.join(', ')}, and about ${f0(m.region.iterations[1])} iterations were needed because the region grows by one pixel layer per iteration.`);
  b.figure('m2_region_grow.png', 'Region growing from a seed on the plate background with tolerance 0.03, 0.08 and 0.20.', { key: 'fig:m2region', width: 560 });

  // ------------------------------------------------------------------ morphology
  b.h3('Morphological operations');
  const c = m.morph.components;
  b.p(`${b.ref('fig:m2morph')} applies the morphological operations to the binarised plate text of the scene after 2 % salt-and-pepper noise had been added. The number of connected components, which should be near that of the clean image, falls from ${c.noisy} in the noisy image to ${c.opened} after a 3 × 3 opening and ${c.openedClosed} after opening followed by closing; the clean image has ${c.clean}.`);
  b.figure('m2_morphology.png', 'Morphological operations on binarised plate text (white = foreground).', { key: 'fig:m2morph', width: 560 });

  // ------------------------------------------------------------------ discussion
  b.h2('Discussion');
  b.bullets([
    `**Canny is the most robust detector.** At the low noise level all three detectors reach F1 = ${f2(e.canny[0].f1)} (within the 2-pixel tolerance). At σ = ${e.sigmas[1]} Sobel and Prewitt still find every true edge pixel (recall ${f2(e.sobel[1].recall)}) but add many isolated noise pixels (precision ${f2(e.sobel[1].precision)} and ${f2(e.prewitt[1].precision)}), while Canny, thanks to smoothing and hysteresis, keeps precision and recall at ${f2(e.canny[1].f1)}. The difference between Sobel and Prewitt (F1 ${f2(e.sobel[1].f1)} against ${f2(e.prewitt[1].f1)}) comes from the automatically chosen thresholds, not from a fundamental property of the kernels, and it is from one image and one noise sample, so we do not conclude that one is better. Canny needs more computation (${f0(m.timing.cannyMs)} ms here).`,
    `**A global threshold fails under uneven lighting.** With a four-fold lighting gradient Otsu’s method lost the dim objects on the left (Dice ${f2(m.seg.otsuDice)}), whereas the adaptive threshold, which compares each pixel with its own neighbourhood, reached ${f2(m.seg.adaptiveDice)}. This only works when the objects are smaller than the window; large uniform objects would become hollow, which was not tested here. In the recogniser, whose characters are small compared with the plate, the adaptive threshold nevertheless did not improve the results (${b.ref('sec:segment')}), so Otsu is the default there.`,
    `**Region growing is precise but needs a seed.** It segmented the chosen object almost perfectly (Dice ${f2(m.seg.regionDice)}), but it cannot find objects by itself and is slow for large regions in this implementation (about ${f0(m.region.iterations[1])} iterations for the plate). It is a tool for interactive use or for refining a region found by other means.`,
    `**Morphology removes most, not all, noise.** The 3 × 3 opening reduced the specks considerably but also removed the thin plate frame, and the combined operation still leaves ${c.openedClosed - c.clean} more components than the clean image. A larger structuring element would remove more noise but would also erode thin strokes of the characters; choosing the size is a trade-off between the two.`,
    `**Labelling is fast enough.** The run-based algorithm labelled a Canny edge map of 640 × 480 pixels in ${f1(m.timing.labelMs)} ms, which is why the detector of Chapter 6 can afford several labelling passes per image.`,
  ]);
};
