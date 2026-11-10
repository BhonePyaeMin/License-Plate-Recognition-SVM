function J = nightVision(I)
%NIGHTVISION  Night-vision copy of a dark photo (for the plate search).
%   J = NIGHTVISION(I)
%   A plate in a night photo sits in the dark part of a picture that is lit by a few lamps: the shadows hide the characters and the
%   glow of a lamp saturates its surroundings. Steps (single-scale retinex, Module 1):
%     1. the illumination is estimated as a very blurred copy of the luminance (the photo is shrunk to about 80 px, blurred with a
%        Gaussian and enlarged again) and divided out in the log domain: the shadows are lifted, the glow of a lamp is flattened;
%     2. the result is stretched between its 1 % and 99.5 % percentiles;
%     3. a 3 x 3 median filter of the luminance reduces the sensor noise that the lifting amplifies;
%     4. every colour channel is multiplied by the gain of the luminance, so the colours of a plate are kept.
%   The copy is searched in addition to the photo itself (RECOGNIZEPLATES option 'NightVision'), it never replaces it.

I = toDouble(I);
Y = toGray(I);
[H, W] = size(Y);
k = max(1, max(H, W) / 80);
small = imResize(Y, 1 / k, 'bilinear');
sg = 3;
small = spatialFilter(small, gaussianKernel(2 * ceil(3 * sg) + 1, sg), 'replicate');
L = imResize(small, [H W], 'bilinear');
eps0 = 0.02;
R = log(Y + eps0) - log(L + eps0);                           % reflectance (the lit scene without the illumination)
q = sort(R(:));
lo = q(max(1, round(0.01 * numel(q))));  hi = q(min(numel(q), round(0.995 * numel(q))));
R = min(max((R - lo) / max(hi - lo, 1e-3), 0), 1);
Rp = [R(1, :); R; R(end, :)];  Rp = [Rp(:, 1), Rp, Rp(:, end)];
St = zeros(H, W, 9);  n = 0;
for dy = 0:2, for dx = 0:2, n = n + 1;  St(:, :, n) = Rp(1 + dy:H + dy, 1 + dx:W + dx); end, end
Rm = median(St, 3);                                           % 3 x 3 median with replicated borders
if size(I, 3) == 3
    J = (I ./ max(Y, 0.02)) .* repmat(Rm, [1 1 3]);               % colour of every pixel (luminance 1) times the new luminance
else
    J = Rm;
end
J = min(max(J, 0), 1);
end
