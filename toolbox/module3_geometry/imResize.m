function J = imResize(I, sz, method, antialias)
%IMRESIZE  Resize an image with nearest / bilinear / bicubic interpolation.
%   J = IMRESIZE(I, scale, method)     scale factor (scalar)
%   J = IMRESIZE(I, [rows cols], method)
%   method    : 'nearest' | 'bilinear' (default) | 'bicubic'
%   antialias : low-pass filter before shrinking (default true)
%
%   Pixel centres are aligned (x_in = (x_out - 0.5)/s + 0.5) and coordinates
%   are clamped, so image borders are replicated instead of turning black.

if nargin < 3 || isempty(method), method = 'bilinear'; end
if nargin < 4, antialias = true; end
I = toDouble(I);
[h, w, ~] = size(I);
if isscalar(sz)
    H = max(1, round(h * sz));  W = max(1, round(w * sz));
else
    H = sz(1);  W = sz(2);
end
sy = H / h;  sx = W / w;
if antialias && (sx < 1 || sy < 1)
    sg = 0.5 / min(sx, sy);                              % blur ~ output pixel footprint
    k = 2*ceil(3*sg) + 1;
    I = spatialFilter(I, gaussianKernel(k, sg));
end
[xo, yo] = meshgrid(1:W, 1:H);
X = (xo - 0.5) / sx + 0.5;
Y = (yo - 0.5) / sy + 0.5;
X = min(max(X, 1), w);   Y = min(max(Y, 1), h);          % clamp -> replicate border
J = interpSample(I, X, Y, method);
J = min(max(J, 0), 1);
end
