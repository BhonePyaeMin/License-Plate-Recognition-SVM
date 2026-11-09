function J = interpSample(I, X, Y, method, fillVal)
%INTERPSAMPLE  Sample an image at non-integer coordinates (Module 3 - interpolation).
%   J = INTERPSAMPLE(I, X, Y, method, fillVal)
%   X, Y   : arrays of the same size holding column (x) and row (y) coordinates,
%            1-based; pixel (r,c) has its centre at x = c, y = r.
%   method : 'nearest' | 'bilinear' | 'bicubic'
%   fillVal: value used for coordinates outside the image (default 0)
%   J has size(X) (x channels).
%
%   nearest  - value of the closest pixel (blocky, fastest)
%   bilinear - weighted mean of the 4 surrounding pixels
%   bicubic  - Keys cubic convolution (a = -0.5) over a 4x4 neighbourhood

if nargin < 4, method = 'bilinear'; end
if nargin < 5, fillVal = 0; end
I = double(I);
[h, w, nc] = size(I);
tol = 1e-6;                                               % absorb floating-point error at the borders
inside = X >= 1 - tol & X <= w + tol & Y >= 1 - tol & Y <= h + tol;
J = zeros([size(X), nc]);

for ch = 1:nc
    A = I(:,:,ch);
    out = fillVal * ones(size(X));
    switch lower(method)
        case 'nearest'
            xi = min(max(round(X), 1), w);
            yi = min(max(round(Y), 1), h);
            v = A(sub2ind([h w], yi, xi));
        case 'bilinear'
            x0 = min(max(floor(X), 1), w);   x1 = min(x0 + 1, w);
            y0 = min(max(floor(Y), 1), h);   y1 = min(y0 + 1, h);
            dx = min(max(X - x0, 0), 1);     dy = min(max(Y - y0, 0), 1);
            v = A(sub2ind([h w], y0, x0)) .* (1-dx) .* (1-dy) + ...
                A(sub2ind([h w], y0, x1)) .* dx     .* (1-dy) + ...
                A(sub2ind([h w], y1, x0)) .* (1-dx) .* dy     + ...
                A(sub2ind([h w], y1, x1)) .* dx     .* dy;
        case 'bicubic'
            x0 = floor(X);  y0 = floor(Y);
            dx = X - x0;    dy = Y - y0;
            v = zeros(size(X));
            for m = -1:2                                     % rows y0-1 .. y0+2
                wy = cubicWeight(dy - m);
                yi = min(max(y0 + m, 1), h);
                for n = -1:2                                 % cols x0-1 .. x0+2
                    wx = cubicWeight(dx - n);
                    xi = min(max(x0 + n, 1), w);
                    v = v + wy .* wx .* A(sub2ind([h w], yi, xi));
                end
            end
        otherwise
            error('interpSample:method', 'Unknown interpolation method "%s".', method);
    end
    out(inside) = v(inside);
    J(:,:,ch) = out;
end
end

function k = cubicWeight(t)
% Keys cubic convolution kernel with a = -0.5.
a = -0.5;
t = abs(t);
k = zeros(size(t));
m1 = t <= 1;
m2 = t > 1 & t < 2;
k(m1) = (a+2)*t(m1).^3 - (a+3)*t(m1).^2 + 1;
k(m2) = a*t(m2).^3 - 5*a*t(m2).^2 + 8*a*t(m2) - 4*a;
end
