function [E, mag, ang] = edgeDetect(I, method, thresh, sigma)
%EDGEDETECT  Sobel, Prewitt and Canny edge detectors (Module 2).
%   [E, mag, ang] = EDGEDETECT(I, method, thresh, sigma)
%   method : 'sobel' | 'prewitt' | 'canny'
%   thresh : fraction (0..1) of the maximum gradient magnitude used as threshold.
%            [] -> chosen automatically with Otsu's method.
%            Canny accepts [low high]; a scalar is the high threshold, low = 0.4*high.
%   sigma  : Gaussian std for Canny pre-smoothing (default 1.4)
%   E      : logical edge map;  mag : gradient magnitude;  ang : direction (rad)
%
%   Sobel/Prewitt: gradient by 3x3 derivative kernels, then thresholding.
%   Canny: Gaussian smoothing -> Sobel gradient -> non-maximum suppression ->
%          double threshold -> hysteresis (weak edges kept only if connected to
%          strong ones).

if nargin < 3, thresh = []; end
if nargin < 4 || isempty(sigma), sigma = 1.4; end
I = toGray(I);

switch lower(method)
    case {'sobel', 'canny'}
        Kx = [-1 0 1; -2 0 2; -1 0 1];                     % Sobel derivative kernel
    case 'prewitt'
        Kx = [-1 0 1; -1 0 1; -1 0 1];
    otherwise
        error('edgeDetect:method', 'Unknown edge detector "%s".', method);
end
Ky = Kx.';

if strcmpi(method, 'canny')
    k = 2*ceil(3*sigma) + 1;
    I = spatialFilter(I, gaussianKernel(k, sigma));
end
Gx = spatialFilter(I, Kx);
Gy = spatialFilter(I, Ky);
mag = hypot(Gx, Gy);
ang = atan2(Gy, Gx);
mx = max(mag(:));
if mx == 0, E = false(size(I)); return; end
n = mag / mx;

if ~strcmpi(method, 'canny')
    if isempty(thresh), thresh = otsuThreshold(n); end
    E = n >= thresh(1);
    return
end

% ---------------- Canny: non-maximum suppression -----------------------------
deg = mod(ang * 180/pi, 180);
sector = zeros(size(deg));                                 % 0, 45, 90, 135 degrees
sector(deg >= 22.5  & deg < 67.5)  = 45;
sector(deg >= 67.5  & deg < 112.5) = 90;
sector(deg >= 112.5 & deg < 157.5) = 135;
[h, w] = size(n);
Np = padImage(n, 1, 1, 'zero');
nb = @(dr, dc) Np(1 + dr + (1:h), 1 + dc + (1:w));
keep = false(h, w);
m = sector == 0;    a = nb(0,1);  b = nb(0,-1);   keep(m) = n(m) >= a(m) & n(m) >= b(m);
m = sector == 45;   a = nb(1,1);  b = nb(-1,-1);  keep(m) = n(m) >= a(m) & n(m) >= b(m);
m = sector == 90;   a = nb(1,0);  b = nb(-1,0);   keep(m) = n(m) >= a(m) & n(m) >= b(m);
m = sector == 135;  a = nb(1,-1); b = nb(-1,1);   keep(m) = n(m) >= a(m) & n(m) >= b(m);
nms = n .* keep;

% ---------------- double threshold + hysteresis ------------------------------
if isempty(thresh)
    hi = otsuThreshold(nms(nms > 0));
    hi = max(hi, 0.05);
    lo = 0.4 * hi;
elseif isscalar(thresh)
    hi = thresh;  lo = 0.4 * hi;
else
    lo = min(thresh);  hi = max(thresh);
end
strong = nms >= hi;
weak   = nms >= lo;
[L, nL] = labelComponents(weak, 8);
if nL == 0, E = false(h, w); return; end
good = false(nL, 1);
good(unique(L(strong & L > 0))) = true;                     % components that contain a strong pixel
E = false(h, w);
E(L > 0) = good(L(L > 0));
end
