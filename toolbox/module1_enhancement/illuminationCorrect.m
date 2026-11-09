function J = illuminationCorrect(I, sigma, strength)
%ILLUMINATIONCORRECT  Flatten uneven lighting (shadow on one half of the plate, a lamp on the other).
%   J = ILLUMINATIONCORRECT(I, sigma, strength)
%   The slowly varying illumination is estimated as a very wide Gaussian blur of the luminance (sigma in
%   pixels of the image width / 1000, so it behaves the same for large and small photos; the blur is
%   computed on a shrunken copy and enlarged again). The picture is divided by it and rescaled to the
%   original mean:   J = I .* (mean(B) ./ B) .^ strength.
%   sigma default 40, strength default 1 (0 = no change). The colours are kept: all channels get the
%   same gain.

if nargin < 2 || isempty(sigma), sigma = 40; end
if nargin < 3 || isempty(strength), strength = 1; end
I = toDouble(I);
[h, w, ~] = size(I);
G = toGray(I);
k = min(1, 200 / max(h, w));                                 % estimate the light on a small copy
Gs = G;  if k < 1, Gs = imResize(G, k, 'bilinear'); end
sg = max(1, sigma * w / 1000 * k);
B = spatialFilter(Gs, gaussianKernel(2 * ceil(3 * sg) + 1, sg), 'symmetric');
if k < 1, B = imResize(B, [h w], 'bilinear'); end
B = max(B, 0.02);
gain = (mean(B(:)) ./ B) .^ strength;
J = min(max(I .* gain, 0), 1);
end
