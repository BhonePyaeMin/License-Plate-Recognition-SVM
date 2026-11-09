'use strict';
// Chapter 3: Module 1 - image enhancement.
const L = require('./lib');
const { M, f0, f1, f2, pct } = L;
const r = (...parts) => parts.map((p) => (typeof p === 'string' ? M.r(p) : p));

module.exports = function m1(b, d) {
  const m = d.m1;
  const fn = d.code.modules.module1_enhancement;

  b.h1('Module 1: Image Enhancement');
  b.p('__Responsible: Student 1__ [[name]]');

  // ------------------------------------------------------------------ objectives
  b.h2('Objectives');
  b.bullets([
    'Histogram processing: equalisation and matching, and gray-level transformations to adjust brightness and contrast.',
    'Spatial filtering: smoothing filters (mean, Gaussian, median) for noise reduction and sharpening filters (Laplacian, high-pass, unsharp masking).',
    'Frequency-domain filtering: Fourier-based low-pass, high-pass and band-pass filters.',
    'For every technique, a function with documented inputs and outputs and a display of the original and enhanced image for comparison.',
  ]);

  // ------------------------------------------------------------------ theory
  b.h2('Theory', { key: 'sec:m1theory' });
  b.h3('Histogram processing');
  b.p('For an image with L gray levels r_k, the normalised histogram p(r_k) = n_k/(MN) is the fraction of pixels at level k, and the cumulative distribution function (CDF) is');
  b.eq(r('cdf', M.rb(M.sub('r', 'k')), '=', M.sum([M.r('p'), M.rb(M.sub('r', 'j'))], 'j=0', 'k')));
  b.p('__Histogram equalisation__ maps every level through the CDF so that the output histogram is approximately flat. With the smallest non-zero CDF value cdf_{min} the transfer function is');
  b.eq(r(M.sub('s', 'k'), '=', M.frac(r('cdf', M.rb(M.sub('r', 'k')), '−', M.sub('cdf', 'min')), r('1', '−', M.sub('cdf', 'min')))));
  b.p('__Histogram matching__ (specification) generalises this: with T the CDF of the input and G the CDF of the reference image, each input level r is mapped to the reference level z for which G(z) is closest to T(r) from above,');
  b.eq(r('z', '=', M.sup('G', '−1'), M.rb(r('T', M.rb('r')))));
  b.p('which is computed with a monotone search over the two CDFs. For colour images only the V channel of the HSV representation is changed, so hue and saturation, and therefore the colours, are preserved.');

  b.h3('Gray-level transformations');
  b.p('Point operations s = T(r) act on every pixel independently. The toolbox implements the linear brightness/contrast transform with gain a and offset b, the gamma transform, the logarithmic transform and a percentile-based contrast stretch:');
  b.eq(r('s', '=', 'a', M.rb(r('r', '−', '0.5')), '+', '0.5', '+', 'b'));
  b.eq(r('s', '=', M.sup('r', 'γ')));
  b.eq(r('s', '=', M.frac(r('log', M.rb(r('1', '+', 'a', 'r'))), r('log', M.rb(r('1', '+', 'a'))))));
  b.p('Gamma below 1 brightens dark regions, gamma above 1 darkens bright ones. The stretch maps the lower and upper percentile (by default 1 % and 99 %) to 0 and 1 and clips the rest, which makes it robust against a few extreme pixels.');

  b.h3('Spatial filtering');
  b.p('A spatial filter replaces each pixel by a weighted sum of its neighbourhood, with weights w(s, t) given by a kernel (correlation):');
  b.eq(r('g', M.rb(r('x', ',', 'y')), '=', M.sum(M.sum(r('w', M.rb(r('s', ',', 't')), 'f', M.rb(r('x', '+', 's', ',', 'y', '+', 't'))), 't'), 's')));
  b.p('The __mean filter__ uses equal weights 1/k² and the __Gaussian filter__ uses w(s, t) ∝ exp(−(s² + t²)/(2σ²)), normalised to sum to one; both are linear and blur edges, the Gaussian less abruptly. '
    + 'The __median filter__ is non-linear: it replaces the pixel by the median of its k × k neighbourhood, which removes isolated outliers (salt-and-pepper noise) without smearing them over the neighbourhood.');
  b.p('Sharpening adds back a measure of local intensity change. The __Laplacian__ (here the eight-neighbour version, whose centre coefficient is negative) is the sum of the eight neighbours minus eight times the centre, and the sharpened image is');
  b.eq(r('g', '=', 'f', '−', 'c', M.rb(r('∇²', 'f'))));
  b.p('__High-pass sharpening__ adds a zero-sum 3 × 3 high-pass response, and __unsharp masking__ (high-boost filtering) subtracts a Gaussian-blurred copy,');
  b.eq(r('g', '=', 'f', '+', 'k', M.rb(r('f', '−', M.sub('f', 'blur')))));
  b.p('with an amount k that controls the strength. All sharpening filters amplify noise together with edges, so they should follow a smoothing step.');

  b.h3('Frequency-domain filtering');
  b.p('Filtering in the Fourier domain multiplies the centred spectrum F(u, v) of the image by a transfer function H(u, v) and transforms back:');
  b.eq(r('g', '=', 'Re', M.cb(r(M.sup('ℱ', '−1'), M.sqb(r('H', M.rb(r('u', ',', 'v')), 'F', M.rb(r('u', ',', 'v'))))))));
  b.p('Let D(u, v) be the distance of the frequency (u, v) from the centre of the spectrum and D₀ the cut-off radius. The three low-pass shapes are');
  b.eq(r(M.sub('H', 'ideal'), '=', M.cb(r('1', ' if ', 'D', '≤', M.sub('D', '0'), ',  ', '0', ' otherwise'))));
  b.eq(r(M.sub('H', 'Butterworth'), '=', M.frac(r('1'), r('1', '+', M.sup(M.sqb(r(M.frac(r('D'), r(M.sub('D', '0'))))), r('2', 'n'))))));
  b.eq(r(M.sub('H', 'Gauss'), '=', M.sup('e', r('−', M.frac(r(M.sup('D', '2')), r('2', M.sup(M.sub('D', '0'), '2')))))));
  b.p('The ideal filter cuts sharply and causes ringing (ripples around edges); the Butterworth filter of order n = 2 has a smooth transition; the Gaussian filter has no ringing at all. '
    + 'The corresponding high-pass filter is H_hp = 1 − H_lp, and a band-pass filter is the difference of two low-pass filters with cut-offs D_hi and D_lo. '
    + 'The implementation zero-pads the image to twice its size to avoid wrap-around of the circular convolution, expresses the cut-off as a fraction of the largest usable frequency radius, and keeps the DC term for high-pass and band-pass filters so that the mean brightness is unchanged.');

  b.h3('Noise models and quality measures');
  b.p('To evaluate denoising, known noise is added: zero-mean __Gaussian__ noise with standard deviation σ, __salt-and-pepper__ noise that sets a fraction of the pixels to black or white, and multiplicative __speckle__ noise. Quality is measured by the mean squared error against the clean image and the peak signal-to-noise ratio, which for images in [0, 1] is');
  b.eq(r('PSNR', '=', '10', M.sub('log', '10'), M.rb(M.frac(r('1'), r('MSE')))), 'eq:psnr');
  b.p('Higher PSNR means a result closer to the clean image.');

  // ------------------------------------------------------------------ implementation
  b.h2('MATLAB implementation', { key: 'sec:m1impl' });
  b.p(`${b.ref('tab:m1funcs')} lists the functions of Module 1 together with the shared helpers they use (<<toDouble>>, <<padImage>>, <<spatialFilter>>, <<gaussianKernel>>, <<imageMetrics>>). The descriptions are taken from the help headers in the code.`);
  b.table(
    [{ h: 'Function', w: 3.6 }, { h: 'Purpose', w: 5.4 }],
    fn.map((f) => [`<<${f.signature}>>`, f.description]),
    'Functions of Module 1 (folder toolbox/module1_enhancement).', { key: 'tab:m1funcs', size: 18 });
  b.p('Implementation notes:');
  b.bullets([
    '**Histograms** are computed with <<accumarray>>: the quantised image is used as the index into a 256-bin counter, so no loop over pixels is needed. Equalisation and matching are then table look-ups.',
    '**Spatial filters** are correlations with an odd-sized kernel through <<conv2>> on a border-padded image (<<padImage>>, replicate/symmetric/zero), so the output has the size of the input and no black frame appears.',
    '**The median filter** stacks the k² shifted copies of the image into a three-dimensional array and takes the median along the third dimension, which is fully vectorised.',
    '**Frequency filtering** builds H(u, v) on the padded frequency grid, applies <<fftshift>> and <<ifftshift>> around the multiplication, crops the result, and also returns H and the log-magnitude spectrum for display.',
    '**Colour images** are handled per channel by the spatial and frequency filters and through the V channel by the histogram operations.',
  ]);

  // ------------------------------------------------------------------ results
  b.h2('Results', { key: 'sec:m1results' });
  b.p(`All Module 1 experiments use one synthetic street scene (a car with a licence plate, 640 × 480 pixels) so that the images relate to the project topic. ${b.ref('fig:m1all')} shows the original and the result of one setting of each technique, as produced by <<compareEnhancement>>.`);
  b.figure('m1_enhancement.png', 'Original image and one result of each Module 1 technique (output of compareEnhancement).', { key: 'fig:m1all', width: 610 });

  b.h3('Histogram processing');
  b.p(`A low-contrast copy of the scene (gray values compressed into [0.30, 0.55]) was equalised and matched to the original scene. ${b.ref('fig:m1hist')} shows the images and their histograms; ${b.ref('tab:m1hist')} gives the statistics.`);
  b.figure('m1_histograms.png', 'Histogram equalisation and histogram matching of a low-contrast image, with the gray-level histograms below.', { key: 'fig:m1hist', width: 610 });
  b.table(
    [{ h: 'Image', w: 3 }, { h: 'Mean', w: 1.2, a: 'r' }, { h: 'Std. deviation', w: 1.6, a: 'r' }, { h: 'Entropy (bits)', w: 1.6, a: 'r' }],
    [
      ['Low-contrast input', f2(m.hist.meanInput), f2(m.hist.stdInput), f2(m.hist.entropyInput)],
      ['After equalisation', '–', f2(m.hist.stdEqualised), f2(m.hist.entropyEqualised)],
      ['After matching to the reference', f2(m.hist.meanMatched), f2(m.hist.stdMatched), '–'],
      ['Reference (well exposed)', f2(m.hist.meanReference), f2(m.hist.stdReference), '–'],
    ], 'Statistics of the histogram experiment.', { key: 'tab:m1hist' });

  b.h3('Noise reduction');
  b.p(`Gaussian noise (σ = 0.08) and salt-and-pepper noise (10 % of the pixels) were added to the scene and removed with four filters each. ${b.ref('fig:m1noise')} shows a close-up of the licence plate area; ${b.ref('tab:m1noise')} gives the PSNR of the whole image against the clean scene.`);
  b.figure('m1_noise.png', 'Noise reduction (close-up of the grille and plate). Top: Gaussian noise. Bottom: salt-and-pepper noise.', { key: 'fig:m1noise', width: 610 });
  const g = m.noise.gaussian; const s = m.noise.saltpepper;
  b.table(
    [{ h: 'Noise', w: 2.4 }, { h: 'Noisy', w: 1, a: 'r' }, { h: 'Mean 3×3', w: 1.1, a: 'r' }, { h: 'Gaussian 5×5', w: 1.3, a: 'r' }, { h: 'Median 3×3', w: 1.2, a: 'r' }, { h: 'Median 5×5', w: 1.2, a: 'r' }, { h: 'FFT low-pass', w: 1.3, a: 'r' }],
    [
      ['Gaussian, σ = 0.08', f1(g.noisy), f1(g.mean3), { t: f1(g.gauss5), b: true }, f1(g.median3), '–', f1(g.fftLowpass)],
      ['Salt and pepper, 10 %', f1(s.noisy), f1(s.mean3), f1(s.gauss5), { t: f1(s.median3), b: true }, f1(s.median5), '–'],
    ], 'PSNR (dB) of the denoised image against the clean image. The FFT low-pass is a Butterworth filter of order 2 with cut-off 0.25. Best value per row in bold.', { key: 'tab:m1noise' });

  b.h3('Sharpening');
  const sh = m.sharpen;
  b.p(`Sharpening was compared by the standard deviation of the Laplacian response, which grows when edges become steeper: the original scene scores ${f3(sh.original)}, Laplacian sharpening (amount 1) ${f3(sh.laplacian)}, high-pass sharpening ${f3(sh.highpass)} and unsharp masking (amount 1.5) ${f3(sh.unsharp)}. `
    + 'These numbers include the camera noise of the scene, which every sharpening filter amplifies as well; the visual comparison in the overview figure shows the same: the Laplacian result has the crispest characters and the most visible noise.');

  b.h3('Frequency-domain filtering');
  b.p(`${b.ref('fig:m1freq')} shows the spectrum of the scene, the three low-pass transfer functions and the filtered results (close-up). ${b.ref('tab:m1freq')} compares the shapes quantitatively, both as a blurring operation (PSNR of the low-pass result against the original, cut-off 0.10) and as a denoiser for the Gaussian-noise image.`);
  b.figure('m1_frequency.png', 'Frequency-domain filtering. Top: input, centred log spectrum and low-pass transfer functions. Bottom: results (close-up) of ideal, Butterworth and Gaussian low-pass, Butterworth high-pass and Gaussian band-pass.', { key: 'fig:m1freq', width: 610 });
  const fq = m.freq;
  b.table(
    [{ h: 'Filter shape', w: 2.2 }, { h: 'Blur: PSNR vs. original (cut-off 0.10)', w: 2.6, a: 'r' }, { h: 'Denoise cut-off 0.15', w: 1.6, a: 'r' }, { h: 'Denoise cut-off 0.25', w: 1.6, a: 'r' }, { h: 'Denoise cut-off 0.35', w: 1.6, a: 'r' }],
    ['ideal', 'butterworth', 'gaussian'].map((k) => [k.charAt(0).toUpperCase() + k.slice(1), f1(fq.lowpassPsnr[k]), f1(fq.denoise[k][0]), f1(fq.denoise[k][1]), f1(fq.denoise[k][2])]),
    `PSNR (dB) of low-pass filtering. The noisy input has ${f1(fq.noisyPsnr)} dB.`, { key: 'tab:m1freq' });

  // ------------------------------------------------------------------ discussion
  b.h2('Discussion');
  b.bullets([
    `**Histogram processing works as designed.** Equalisation raised the standard deviation of the low-contrast image from ${f2(m.hist.stdInput)} to ${f2(m.hist.stdEqualised)}. Its entropy fell slightly (${f2(m.hist.entropyInput)} to ${f2(m.hist.entropyEqualised)} bits), which is expected for a discrete many-to-one mapping: equalisation spreads the levels but cannot add information. Matching to the reference produced a mean of ${f2(m.hist.meanMatched)} and a standard deviation of ${f2(m.hist.stdMatched)} against ${f2(m.hist.meanReference)} and ${f2(m.hist.stdReference)} for the reference.`,
    `**The right denoising filter depends on the noise.** For salt-and-pepper noise the 3 × 3 median filter improved the PSNR from ${f1(s.noisy)} to ${f1(s.median3)} dB, about ${f1(s.median3 - s.gauss5)} dB better than the Gaussian and ${f1(s.median3 - s.mean3)} dB better than the mean filter, which smear the outliers over their neighbours. A larger 5 × 5 median (${f1(s.median5)} dB) removes thin structures such as the grille slats, so the smallest window that removes the noise is preferable. For Gaussian noise the linear filters win: the Gaussian 5 × 5 (${f1(g.gauss5)} dB) is better than the median (${f1(g.median3)} dB).`,
    `**Filter shape matters in the frequency domain.** At the same cut-off the ideal low-pass filter produced the lowest PSNR (${f1(fq.lowpassPsnr.ideal)} dB) and visible ringing around the characters, the Butterworth filter ${f1(fq.lowpassPsnr.butterworth)} dB, and the Gaussian filter the highest (${f1(fq.lowpassPsnr.gaussian)} dB) without ringing. The same order held for denoising at all three cut-offs, for example ${f1(fq.denoise.gaussian[1])}, ${f1(fq.denoise.butterworth[1])} and ${f1(fq.denoise.ideal[1])} dB at cut-off 0.25. Higher cut-offs gave better PSNR here because the scene is dominated by low frequencies while the noise is spread over all frequencies.`,
    '**Sharpening needs clean input.** Every sharpening filter increased the edge energy, but also the visible noise. For this reason the plate detector of Chapter 6 smooths with a Gaussian filter and does not sharpen.',
    '**Limits.** The experiments use one scene and one noise realisation per noise type, so the PSNR differences of a few tenths of a dB (for example between the mean and Gaussian filters on Gaussian noise) should not be over-interpreted; the large differences (median versus linear filters on impulse noise) are robust.',
  ]);
};

function f3(x) { return Number(x).toFixed(3); }
