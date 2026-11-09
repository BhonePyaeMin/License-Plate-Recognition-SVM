'use strict';
// Chapter 5: Module 3 - geometric transformations, interpolation and registration.
const L = require('./lib');
const { M, f0, f1, f2, pct } = L;
const r = (...parts) => parts.map((p) => (typeof p === 'string' ? M.r(p) : p));

module.exports = function m3(b, d) {
  const fn = d.code.modules.module3_geometry;

  b.h1('Module 3: Geometric Transformations and Interpolation');
  b.p('__Responsible: Student 3__ [[name]]');

  b.h2('Objectives');
  b.bullets([
    'Image translation, scaling (zooming), rotation and general affine transformations.',
    'Forward and reverse mapping for image warping.',
    'Correction of radial lens distortion.',
    'Nearest-neighbour, bilinear and bicubic interpolation for resizing and transformation.',
    'Optional and advanced: a basic image registration algorithm based on feature matching.',
    'Integration of the three modules into one toolbox (graphical interface) and testing of the whole.',
  ]);

  // ------------------------------------------------------------------ theory
  b.h2('Theory', { key: 'sec:m3theory' });
  b.h3('Transformations in homogeneous coordinates');
  b.p('A point (x, y) is written as the column vector [x y 1]ᵀ so that translations as well as linear maps become matrix products. A transformation T maps an input point to an output point, [x′ y′ 1]ᵀ = T [x y 1]ᵀ. The elementary transformations are');
  b.table(
    [{ h: 'Transformation', w: 2.2 }, { h: 'Matrix T', w: 4.6 }, { h: 'Parameters', w: 2.6 }],
    [
      ['Translation', '[1 0 t_x; 0 1 t_y; 0 0 1]', 'shift (t_x, t_y) in pixels'],
      ['Scaling', '[s_x 0 0; 0 s_y 0; 0 0 1]', 'zoom factors s_x, s_y'],
      ['Rotation', '[cosθ sinθ 0; −sinθ cosθ 0; 0 0 1]', 'angle θ (counter-clockwise on screen, y axis points down)'],
      ['Shear', '[1 h_x 0; h_y 1 0; 0 0 1]', 'shear factors h_x, h_y'],
      ['General affine', '[a b t_x; c d t_y; 0 0 1]', 'six free parameters'],
    ], 'Elementary geometric transformations.', { key: 'tab:transforms' });
  b.p('Transformations are composed by multiplying their matrices. Scaling and rotation of an image act about the origin, so about the image centre c the operation is T = T_c · R · T_c⁻¹, where T_c translates the origin to c.');

  b.h3('Forward and reverse mapping');
  b.p('__Forward mapping__ takes every input pixel (x, y), computes where it lands, (x′, y′) = T(x, y), and writes its value there. Because (x′, y′) is rarely an integer position, the value has to be rounded to a pixel, and when the image is enlarged some output pixels receive no value at all (holes) while others receive several. '
    + '__Reverse mapping__ instead visits every output pixel (x′, y′), computes the source position with the inverse transform,');
  b.eq(r(M.rb(r('x', ',', 'y')), '=', M.sup('T', '−1'), M.rb(r('x′', ',', 'y′'))));
  b.p('and interpolates the input image at that position. Every output pixel gets a value, so there are no holes; this is the method used by all geometric functions, while forward mapping is provided to demonstrate the problem.');

  b.h3('Interpolation');
  b.p('The source position found by reverse mapping is generally non-integer, so a value has to be estimated from the surrounding pixels. __Nearest-neighbour__ interpolation copies the closest pixel: it is the fastest and exact for integer shifts, but makes edges jagged. __Bilinear__ interpolation weights the four surrounding pixels f_00, f_10, f_01 and f_11 with the fractional offsets a = x − ⌊x⌋ and c = y − ⌊y⌋:');
  b.eq(r('f', M.rb(r('x', ',', 'y')), '=', M.rb(r('1', '−', 'a')), M.rb(r('1', '−', 'c')), M.sub('f', '00'), '+', 'a', M.rb(r('1', '−', 'c')), M.sub('f', '10'), '+', M.rb(r('1', '−', 'a')), 'c', M.sub('f', '01'), '+', 'a', 'c', M.sub('f', '11')));
  b.p('__Bicubic__ interpolation uses the 4 × 4 neighbourhood with the cubic convolution kernel of Keys (parameter α = −0.5), which reproduces linear and quadratic functions exactly and preserves edges better than bilinear interpolation:');
  b.eq(r('w', M.rb('t'), '=', M.cb(r(M.rb(r('α', '+', '2')), M.sup('|t|', '3'), '−', M.rb(r('α', '+', '3')), M.sup('|t|', '2'), '+', '1', '  (|t| ≤ 1);  ', 'α', M.sup('|t|', '3'), '−', '5', 'α', M.sup('|t|', '2'), '+', '8', 'α', '|t|', '−', '4', 'α', '  (1 < |t| < 2);  0 otherwise'))));
  b.p('Resizing uses reverse mapping with aligned pixel centres, x_in = (x_out − 0.5)/s + 0.5 for scale s, and clamps the coordinates so that the border pixels are replicated instead of turning black. When an image is shrunk, a Gaussian low-pass filter with σ = 0.5/s is applied first to avoid aliasing.');

  b.h3('Radial lens distortion');
  b.p('Wide-angle lenses bend straight lines near the image border. The Brown model describes the distorted position of a point in normalised coordinates (origin at the image centre, radius 1 at the corner):');
  b.eq(r(M.sub('x', 'd'), '=', M.sub('x', 'u'), M.rb(r('1', '+', M.sub('k', '1'), M.sup(M.sub('r', 'u'), '2'), '+', M.sub('k', '2'), M.sup(M.sub('r', 'u'), '4')))));
  b.p('Negative k₁ gives barrel distortion and positive k₁ pincushion distortion. Correcting a photo is reverse mapping: for each pixel of the corrected image the distorted position is computed with the equation above and interpolated. Simulating the distortion (used for testing) needs the inverse of the model, which is obtained by the fixed-point iteration x_u ← x_d / (1 + k₁ r_u² + k₂ r_u⁴), repeated 20 times.');

  b.h3('Image registration');
  b.p('Registration finds the transformation that aligns a moving image with a fixed image. Two methods are implemented. __Phase correlation__ finds a pure translation from the normalised cross-power spectrum of the two images:');
  b.eq(r('R', '=', M.frac(r(M.sub('F', '1'), M.sup(M.sub('F', '2'), '*')), r('|', M.sub('F', '1'), M.sup(M.sub('F', '2'), '*'), '|')), '          ', M.rb('Δx, Δy'), '=', M.lim(r('argmax'), r('x,y')), M.sup('ℱ', '−1'), M.rb('R')));
  b.p('The __feature-based method__ handles rotation, translation and moderate scaling: (1) Harris corners are detected from the structure tensor M of the gradients, R = det M − κ tr²M with κ = 0.04; (2) each corner is described by a 17 × 17 patch normalised to zero mean and unit norm; (3) corners are matched by normalised cross-correlation, keeping only mutual best matches whose score is clearly better than that of the second-best candidate (ratio test); (4) RANSAC repeatedly fits an affine transformation to three random matches and keeps the model with the most inliers (distance below 3 pixels), which is finally refitted to all inliers by least squares; (5) the moving image is warped with reverse mapping.');

  // ------------------------------------------------------------------ implementation
  b.h2('MATLAB implementation', { key: 'sec:m3impl' });
  b.table(
    [{ h: 'Function', w: 3.6 }, { h: 'Purpose', w: 5.4 }],
    fn.map((f) => [`<<${f.signature}>>`, f.description]),
    'Functions of Module 3 (folder toolbox/module3_geometry).', { key: 'tab:m3funcs', size: 18 });
  b.p('Implementation notes:');
  b.bullets([
    '**One warping engine.** <<warpImage>> takes a 3 × 3 matrix, builds the output pixel grid with <<meshgrid>>, applies <<T \\ points>> to obtain the source positions and calls <<interpSample>>. <<geometricTransforms>> only builds the matrix (and the larger canvas for a full rotation), so translation, scaling, rotation, shear and affine maps share the same, tested code.',
    '**Interpolation by index arithmetic.** <<interpSample>> works on arrays of coordinates; for the bicubic case it accumulates the 16 weighted neighbours in two nested loops over the kernel offsets, with clamped indices at the border and a small tolerance (10⁻⁶ pixel) so that floating-point error does not turn border pixels black.',
    '**Forward mapping** writes values with <<accumarray>>; the bilinear variant splats each input pixel onto its four output neighbours with bilinear weights and normalises by the accumulated weight. Output pixels that receive no weight stay at the fill value, which is how the holes are measured.',
    '**Registration** reuses Module 2 for local-maximum detection (<<morphOp>> dilation) and Module 1 for the Gaussian window, and returns the transformation matrix, the registered image and diagnostics (matches, inliers or shift).',
  ]);

  require('./sec_m3_results')(b, d, { r });
};
