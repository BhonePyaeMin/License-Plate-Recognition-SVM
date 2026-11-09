function pts = harrisCorners(I, maxPts, sigma)
%HARRISCORNERS  Harris corner detector. Returns up to maxPts corners as [x y score].
%   pts = HARRISCORNERS(I, maxPts, sigma)
%   R = det(M) - 0.04*trace(M)^2 with M the Gaussian-weighted structure tensor.
%   Corners are the strongest local maxima of R in a 7x7 neighbourhood.

if nargin < 2 || isempty(maxPts), maxPts = 300; end
if nargin < 3 || isempty(sigma),  sigma = 1.5; end
G = toGray(I);
dx = [-1 0 1; -2 0 2; -1 0 1] / 8;
Ix = spatialFilter(G, dx);
Iy = spatialFilter(G, dx.');
g = gaussianKernel(2*ceil(3*sigma) + 1, sigma);
Sxx = spatialFilter(Ix.^2, g);
Syy = spatialFilter(Iy.^2, g);
Sxy = spatialFilter(Ix.*Iy, g);
R = (Sxx.*Syy - Sxy.^2) - 0.04 * (Sxx + Syy).^2;
% A few very strong corners (e.g. the black wedges left by a rotation) must not
% hide the genuine ones, so keep the strongest maxPts local maxima instead of
% thresholding relative to the global maximum.
isMax = R == morphOp(R, 'dilate', true(7)) & R > 1e-4 * max(R(:));
[h, w] = size(G);
border = 12;                                              % keep room for the descriptor patch
isMax([1:border, h-border+1:h], :) = false;
isMax(:, [1:border, w-border+1:w]) = false;
[y, x] = find(isMax);
score = R(isMax);
[score, order] = sort(score, 'descend');
x = x(order);  y = y(order);
n = min(maxPts, numel(x));
pts = [x(1:n), y(1:n), score(1:n)];
end
