function J = smoothFilter(I, type, k, sigma)
%SMOOTHFILTER  Spatial smoothing filters for noise reduction (Module 1).
%   J = SMOOTHFILTER(I, type, k, sigma)
%   type : 'mean'     - k x k box average (linear, blurs edges)
%          'gaussian' - k x k Gaussian with std sigma (default k/6)
%          'median'   - k x k median (non-linear, removes salt & pepper noise)
%   k    : odd window size (default 3)

if nargin < 3 || isempty(k), k = 3; end
if nargin < 4, sigma = []; end
k = 2*floor(k/2) + 1;                               % force odd size
I = toDouble(I);
switch lower(type)
    case 'mean'
        J = spatialFilter(I, ones(k)/k^2);
    case 'gaussian'
        J = spatialFilter(I, gaussianKernel(k, sigma));
    case 'median'
        r = (k-1)/2;
        [h, w, nc] = size(I);
        P = padImage(I, r, r, 'replicate');
        J = zeros(h, w, nc);
        for ch = 1:nc
            S = zeros(h, w, k*k);                    % stack of all k*k shifted copies
            n = 0;
            for dy = 0:k-1
                for dx = 0:k-1
                    n = n + 1;
                    S(:,:,n) = P(dy + (1:h), dx + (1:w), ch);
                end
            end
            J(:,:,ch) = median(S, 3);                % per-pixel median over the window
        end
    otherwise
        error('smoothFilter:type', 'Unknown smoothing filter "%s".', type);
end
end
