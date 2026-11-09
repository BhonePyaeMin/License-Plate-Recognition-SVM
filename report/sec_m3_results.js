'use strict';
// Results and discussion of Chapter 5 (Module 3).
const L = require('./lib');
const { f0, f1, f2, pct } = L;

module.exports = function m3results(b, d) {
  const m = d.m3;
  b.h2('Results', { key: 'sec:m3results' });

  b.h3('Geometric transformations');
  b.p(`${b.ref('fig:m3geo')} shows the transformations on the synthetic scene (output of <<compareGeometry>>): translation, scaling, rotation with the same and with an enlarged canvas, shear, forward and reverse mapping of the same scaling, barrel distortion with its correction, and two enlarged crops that expose the difference between nearest-neighbour and bicubic interpolation.`);
  b.figure('m3_geometry.png', 'Geometric transformations, mapping and interpolation on the synthetic scene.', { key: 'fig:m3geo', width: 610 });

  b.h3('Interpolation');
  b.p(`${b.ref('fig:m3interp')} enlarges a 20 × 50 pixel patch of the plate text eight times with each method. Nearest-neighbour interpolation shows the original pixels as blocks, bilinear interpolation smooths them, and bicubic interpolation keeps the strokes sharper. For a quantitative comparison the scene was shrunk to half size and enlarged again, and rotated by 10° and back by −10°; ${b.ref('tab:m3interp')} gives the PSNR against the original (central region for the rotation, to exclude the corners that leave the image) and the time for enlarging the 640 × 480 image by a factor of two.`);
  b.figure('m3_interp.png', 'Interpolation methods on a patch of the licence plate text, enlarged 8 times.', { key: 'fig:m3interp', width: 560 });
  const ip = m.interp;
  b.table(
    [{ h: 'Method', w: 2 }, { h: 'Shrink and enlarge (dB)', w: 2.4, a: 'r' }, { h: 'Rotate and back (dB)', w: 2.2, a: 'r' }, { h: 'Enlarge 2× (ms)', w: 1.8, a: 'r' }],
    ['nearest', 'bilinear', 'bicubic'].map((k) => [k.charAt(0).toUpperCase() + k.slice(1), f1(ip.resizeRoundTrip[k]), f1(ip.rotateRoundTrip[k]), f0(ip.enlargeMs[k])]),
    'Quality and cost of the interpolation methods.', { key: 'tab:m3interp' });

  b.h3('Forward and reverse mapping');
  const mp = m.mapping;
  b.p(`A white image was scaled by 1.6 with forward mapping (nearest and bilinear splatting) and with reverse mapping, and the fraction of output pixels that received no value was counted. Forward mapping with nearest-neighbour rounding left ${f1(mp.forwardNearestHolesPct)} % of the pixels empty, close to the ${f1(100 * (1 - 1 / 1.6 ** 2))} % that follows from the area ratio 1 − 1/1.6²; bilinear splatting left ${f1(mp.forwardBilinearHolesPct)} % at this scale, and reverse mapping left ${f1(mp.reverseHolesPct)} %. The effect can be seen in the lower panels of ${b.ref('fig:m3geo')}.`);

  b.h3('Radial distortion');
  const rd = m.radial;
  b.p(`A grid of straight lines was distorted with barrel (k₁ = ${rd.barrel.k1}) and pincushion (k₁ = ${rd.pincushion.k1}) distortion and corrected again with the same parameters (${b.ref('fig:m3radial')}). The lines become straight again; ${b.ref('tab:m3radial')} gives the PSNR of the central region against the original grid before and after the correction.`);
  b.figure('m3_radial.png', 'Barrel (top) and pincushion (bottom) distortion of a grid and its correction. Points of the distorted image that have no source point are black.', { key: 'fig:m3radial', width: 560 });
  b.table(
    [{ h: 'Distortion', w: 2.4 }, { h: 'Distorted vs. original (dB)', w: 2.6, a: 'r' }, { h: 'Corrected vs. original (dB)', w: 2.6, a: 'r' }],
    [[`Barrel, k₁ = ${rd.barrel.k1}`, f1(rd.barrel.psnrDistorted), f1(rd.barrel.psnrCorrected)], [`Pincushion, k₁ = ${rd.pincushion.k1}`, f1(rd.pincushion.psnrDistorted), f1(rd.pincushion.psnrCorrected)]],
    `PSNR of a thin-line grid (central region). For the synthetic scene, simulating and correcting a distortion with k₁ = −0.25 gave ${f1(rd.sceneRoundTripPsnr)} dB.`, { key: 'tab:m3radial' });

  b.h3('Image registration');
  const rg = m.reg;
  b.p(`The scene was rotated by 8° and shifted by (12, −7) pixels and registered back to the original. ${b.ref('fig:m3reg')} shows the images and the differences. The feature-based method found ${rg.features.matches} matches of which ${rg.features.inliers} were inliers, estimated the transformation with a rotation error of ${f2(rg.features.rotationErrorDeg)}° and a mean error of ${f2(rg.features.meanPointErrorPx)} pixels at a grid of test points, and improved the PSNR in the central region from ${f1(rg.features.psnrBefore)} to ${f1(rg.features.psnrAfter)} dB in ${f1(rg.featuresSeconds)} s. Phase correlation recovered a pure shift of (9, −5) pixels exactly (found: ${rg.phase.shiftFound.join(', ')}; expected: ${rg.phase.shiftExpected.join(', ')}; the sign is that of the correction).`);
  b.figure('m3_registration.png', 'Image registration by feature matching.', { key: 'fig:m3reg', width: 610 });

  b.h2('Discussion');
  b.bullets([
    `**Bicubic interpolation is the most accurate but the most expensive.** It gave the best PSNR in both round trips (${f1(ip.resizeRoundTrip.bicubic)} dB against ${f1(ip.resizeRoundTrip.bilinear)} dB for bilinear when resizing, and ${f1(ip.rotateRoundTrip.bicubic)} dB against ${f1(ip.rotateRoundTrip.bilinear)} dB when rotating), and the sharpest enlarged strokes, but took ${f1(ip.enlargeMs.bicubic / ip.enlargeMs.bilinear)} times as long as bilinear interpolation in this implementation. For nearest-neighbour the rotation round trip (${f1(ip.rotateRoundTrip.nearest)} dB) was as good as for bilinear (${f1(ip.rotateRoundTrip.bilinear)} dB) because bilinear interpolation blurs a little at each of the two steps, but the blocky result of nearest-neighbour enlargement is visible in ${b.ref('fig:m3interp')}. The recogniser uses bilinear interpolation, which is a good compromise for resizing and de-skewing characters.`,
    `**Reverse mapping is necessary for enlargement.** Forward mapping with rounding left ${f1(mp.forwardNearestHolesPct)} % of the output empty at scale 1.6. Splatting each input pixel on its four neighbours filled all holes at this scale, but it is a more complicated and slower method, and it would leave holes again for larger scale factors (not tested).`,
    `**Distortion correction is accurate where a solution exists.** The correction removes the curvature of the lines; the remaining PSNR difference to the original grid comes from the interpolation blur of thin lines (a thin-line grid is a severe test, because a sub-pixel shift changes many pixels). The inverse of the distortion model does not exist for the outer part of the image under strong barrel distortion (the largest reachable radius for k₁ = −0.3 is about 0.70 of the corner radius); the implementation detects this and leaves those pixels black. A first version used a fixed-point iteration for the inverse and produced noise in that region, which was found when preparing the figure for this report and fixed with Newton’s method (${b.ref('tab:defects')}).`,
    `**Registration works for moderate motion.** The feature-based method recovered a rotation of 8° and a shift to a mean error of ${f2(rg.features.meanPointErrorPx)} pixels. It relies on corner patches that are not rotation invariant, so it will fail for large rotations (we did not test where the limit is), and it needs enough texture. Phase correlation is exact for pure translations and very fast but cannot handle rotation.`,
    '**Limits.** All measurements use one synthetic scene and one transformation per test, so they show that the functions are correct, not how they behave on arbitrary photographs.',
  ]);
};
