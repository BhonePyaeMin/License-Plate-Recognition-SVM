'use strict';
// Chapter 4: Module 2 - segmentation, edge detection and morphology.
const L = require('./lib');
const { M, f0, f1, f2, pct } = L;
const r = (...parts) => parts.map((p) => (typeof p === 'string' ? M.r(p) : p));

module.exports = function m2(b, d) {
  const m = d.m2;
  const fn = d.code.modules.module2_segmentation;

  b.h1('Module 2: Segmentation and Edge Detection');
  b.p('__Responsible: Student 2__ [[name]]');

  b.h2('Objectives');
  b.bullets([
    'Edge detection with the Sobel, Prewitt and Canny operators, and a function that compares them.',
    'Segmentation by thresholding (Otsu’s method), region growing, and colour segmentation in RGB and HSV space.',
    'Morphological operations (dilation, erosion, opening, closing) for refining segmented images, and shape-based segmentation.',
    'Visual and quantitative comparisons between the techniques.',
  ]);

  // ------------------------------------------------------------------ theory
  b.h2('Theory', { key: 'sec:m2theory' });
  b.h3('Gradient-based edge detection');
  b.p('An edge is a place where the intensity changes quickly, so it can be found from the image gradient. The Sobel and Prewitt operators approximate the horizontal derivative G_x with a 3 × 3 kernel that differentiates in one direction and smooths in the other; the vertical derivative G_y uses the transposed kernel. Sobel weights the central row by 2, Prewitt weights all rows equally:');
  b.table(
    [{ h: 'Operator', w: 1.6 }, { h: 'Kernel for G_x', w: 3 }, { h: 'Kernel for G_y', w: 3 }],
    [
      ['Sobel', '[−1 0 1; −2 0 2; −1 0 1]', '[−1 −2 −1; 0 0 0; 1 2 1]'],
      ['Prewitt', '[−1 0 1; −1 0 1; −1 0 1]', '[−1 −1 −1; 0 0 0; 1 1 1]'],
    ], 'Derivative kernels of the Sobel and Prewitt operators.', { key: 'tab:kernels' });
  b.p('The gradient magnitude and direction follow from the two responses, and a pixel is marked as an edge when the magnitude exceeds a threshold:');
  b.eq(r('|', '∇', 'f', '|', '=', M.sqrt(r(M.sup(M.sub('G', 'x'), '2'), '+', M.sup(M.sub('G', 'y'), '2'))), '          ', 'θ', '=', 'atan2', M.rb(r(M.sub('G', 'y'), ',', M.sub('G', 'x')))));
  b.p('The toolbox takes the threshold as a fraction of the largest magnitude; if none is given it is chosen automatically with Otsu’s method applied to the magnitude image.');
  b.p('The __Canny detector__ improves on plain thresholding with five steps: (1) Gaussian smoothing with standard deviation σ (default 1.4) to suppress noise; (2) Sobel gradient magnitude and direction; (3) __non-maximum suppression__, which keeps a pixel only if its magnitude is not smaller than that of its two neighbours along the gradient direction (quantised to 0°, 45°, 90° and 135°), thinning edges to one pixel; (4) a __double threshold__ with a high value t_h and a low value t_l = 0.4 t_h; (5) __hysteresis__: weak edge pixels (above t_l) are kept only if their connected component contains a strong pixel (above t_h). The result is thin, connected edges with few isolated noise pixels.');

  b.h3('Thresholding');
  b.p('__Otsu’s method__ chooses the global threshold k that maximises the between-class variance of the two pixel classes (background and foreground) it creates. With the class probability ω(k), the cumulative mean μ(k) and the global mean μ_T of the normalised histogram:');
  b.eq(r(M.sup(M.sub('σ', 'B'), '2'), M.rb('k'), '=', M.frac(r(M.sup(M.sqb(r(M.sub('μ', 'T'), 'ω', M.rb('k'), '−', 'μ', M.rb('k'))), '2')), r('ω', M.rb('k'), M.rb(r('1', '−', 'ω', M.rb('k')))))), 'eq:otsu');
  b.p('The threshold k* is the maximiser. The function also returns the separability measure η = σ_B²(k*)/σ_T² ∈ [0, 1], which is close to 1 for a clearly bimodal histogram. A global threshold fails when the illumination varies across the image, so an __adaptive threshold__ compares each pixel with the mean of its own window, foreground when f(x, y) < mean_{window}(x, y) − C (dark objects) or f > mean_{window} + C (bright objects).');

  b.h3('Region growing and colour segmentation');
  b.p('__Region growing__ starts from one or more seed pixels, computes a reference intensity m (the mean of the 3 × 3 neighbourhoods around the seeds) and repeatedly adds neighbouring pixels that satisfy |f(x, y) − m| ≤ τ, until no pixel is added. Implemented as dilation restricted to the candidate mask, each iteration grows the region by one pixel layer.');
  b.p('__Colour segmentation__ selects the pixels whose colour lies in a range. In HSV space, where hue H separates colour from brightness V and saturation S, a range such as “yellow” is a simple box; in RGB space the box is given directly by the three channels. The toolbox provides box presets for white, yellow, blue, red, green and black (for example white: S ≤ 0.25 and V ≥ 0.62; yellow: 0.09 ≤ H ≤ 0.20, S ≥ 0.35, V ≥ 0.40) and accepts custom ranges. The hue range may wrap through 0, which is needed for red.');

  b.h3('Morphological operations');
  b.p('Morphology probes an image with a small structuring element (SE) B. For a binary or gray-scale image A the flat dilation and erosion are the maximum and minimum over the SE:');
  b.eq(r(M.rb(r('A', '⊕', 'B')), M.rb(r('x')), '=', M.lim(r('max'), r('b', '∈', 'B')), 'A', M.rb(r('x', '−', 'b')), '          ', M.rb(r('A', '⊖', 'B')), M.rb('x'), '=', M.lim(r('min'), r('b', '∈', 'B')), 'A', M.rb(r('x', '+', 'b'))));
  b.p('__Opening__ (erosion then dilation) removes objects smaller than the SE, __closing__ (dilation then erosion) fills gaps and holes smaller than the SE, and the __morphological gradient__ (dilation minus erosion) outlines objects. Top-hat and black-hat (image minus opening, closing minus image) extract small bright or dark details. '
    + 'Shape-based segmentation combines morphology with __connected-component analysis__: after labelling the components, only those whose area, bounding-box aspect ratio and extent (area divided by bounding-box area) match the expected shape are kept; this is how the plate detector selects plate-like blobs (Chapter 6).');

  // ------------------------------------------------------------------ implementation
  b.h2('MATLAB implementation', { key: 'sec:m2impl' });
  b.table(
    [{ h: 'Function', w: 3.6 }, { h: 'Purpose', w: 5.4 }],
    fn.map((f) => [`<<${f.signature}>>`, f.description]),
    'Functions of Module 2 (folder toolbox/module2_segmentation).', { key: 'tab:m2funcs', size: 18 });
  b.p('Implementation notes:');
  b.bullets([
    '**Connected components without <<bwlabel>>.** <<labelComponents>> first compresses each image row into runs of foreground pixels, then merges runs that overlap in adjacent rows with a union–find structure (4- or 8-connectivity), and finally paints the labels. The cost depends on the number of runs, not pixels, which makes labelling practical in interpreted MATLAB. It is checked against a flood-fill reference on random images (Chapter 8).',
    '**Morphology** uses maximum/minimum filters over the SE offsets. For rectangular SEs the filter is separable (a vertical pass, then a horizontal pass), which turns a 3 × 60 rectangle from 180 to 63 shifts. Padding with −∞ (dilation) or +∞ (erosion) keeps the borders from being eroded or dilated artificially, and the dilation uses the reflected SE so even-sized elements are handled correctly. The same code serves binary and gray-scale images.',
    '**Canny hysteresis** reuses <<labelComponents>>: the weak-edge map is labelled and the components that contain at least one strong pixel are kept.',
    '**Region growing** is written as iterated 3 × 3 dilation (<<conv2>>) of the region masked by the candidate set, which avoids a queue and loops.',
    '**<<fillHoles>>** labels the background with 4-connectivity; background components that do not touch the image border are holes and are filled.',
    '**Structuring elements** (<<makeSE>>) can be rectangles, squares, discs, diamonds, crosses and lines at any angle.',
  ]);

  // RESULTS-AND-DISCUSSION-PLACEHOLDER
  require('./sec_m2_results')(b, d, { m, r });
};
