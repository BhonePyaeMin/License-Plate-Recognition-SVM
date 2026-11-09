function K = gaussianKernel(k, sigma)
%GAUSSIANKERNEL  Normalised 2-D Gaussian kernel of odd size k x k.
%   K = GAUSSIANKERNEL(k, sigma). If sigma is omitted, sigma = k/6.

if mod(k,2) == 0, k = k + 1; end
if nargin < 2 || isempty(sigma), sigma = k/6; end
r = (k-1)/2;
[x, y] = meshgrid(-r:r, -r:r);
K = exp(-(x.^2 + y.^2) / (2*sigma^2));
K = K / sum(K(:));
end
