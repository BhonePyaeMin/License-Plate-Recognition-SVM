function J = deblurRL(I, sigma, iterations)
%DEBLURRL  Richardson-Lucy deconvolution of an out-of-focus / lightly blurred picture (Module 1).
%   J = DEBLURRL(I, sigma, iterations)
%   Model: observed = true image convolved with a Gaussian point-spread function of std sigma (pixels).
%   Richardson-Lucy keeps a guess E of the true image and repeats
%        E <- E .* ( PSF * ( observed ./ (PSF * E) ) )          (* = convolution, the PSF is symmetric)
%   which makes the blurred guess agree with the observation while keeping E positive. A few iterations
%   sharpen the characters; too many amplify noise and create ringing around edges, so the default is
%   modest (sigma 1.5, 10 iterations). Motion blur is not a Gaussian: it is only partly corrected.
%   For colour images only the V channel of HSV is deblurred.

if nargin < 2 || isempty(sigma), sigma = 1.5; end
if nargin < 3 || isempty(iterations), iterations = 10; end
I = toDouble(I);
if size(I, 3) == 3
    hsv = rgb2hsv(I);
    hsv(:,:,3) = deblurRL(hsv(:,:,3), sigma, iterations);
    J = hsv2rgb(hsv);
    return
end
psf = gaussianKernel(2 * ceil(3 * sigma) + 1, sigma);
obs = max(I, 1e-3);
E = obs;
for it = 1:round(iterations)
    est = max(spatialFilter(E, psf, 'symmetric'), 1e-3);
    E = E .* spatialFilter(obs ./ est, psf, 'symmetric');
    E = min(max(E, 1e-3), 1);
end
J = E;
end
