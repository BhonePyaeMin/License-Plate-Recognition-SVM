function [T, registered, info] = registerImages(fixed, moving, method)
%REGISTERIMAGES  Align a moving image to a fixed image (Module 3 - optional, advanced).
%   [T, registered, info] = REGISTERIMAGES(fixed, moving, method)
%   method : 'features' (default) - Harris corners + patch NCC matching + RANSAC affine
%            'phase'              - phase correlation (translation only, FFT based)
%   T          : 3x3 matrix mapping MOVING coordinates to FIXED coordinates
%   registered : moving image warped into the frame of FIXED
%   info       : struct with the number of matches / inliers or the shift found
%
%   'features' copes with moderate rotation (<~20 deg), translation and scaling
%   (<~1.3x) because it estimates a full affine model from the matches.

if nargin < 3, method = 'features'; end
F = toGray(fixed);  M = toGray(moving);
info = struct();

switch lower(method)
    case 'phase'
        sz = [max(size(F,1), size(M,1)), max(size(F,2), size(M,2))];
        A = fft2(F, sz(1), sz(2));  B = fft2(M, sz(1), sz(2));
        R = A .* conj(B);
        R = R ./ max(abs(R), eps);                         % normalised cross-power spectrum
        c = real(ifft2(R));
        [~, k] = max(c(:));
        [r, cc] = ind2sub(size(c), k);
        dy = r - 1;  dx = cc - 1;
        if dy > sz(1)/2, dy = dy - sz(1); end
        if dx > sz(2)/2, dx = dx - sz(2); end
        T = [1 0 dx; 0 1 dy; 0 0 1];
        info.shift = [dx dy];

    case 'features'
        pf = harrisCorners(F, 300);   pm = harrisCorners(M, 300);
        half = 8;
        df = patchDescriptors(F, pf, half);
        dm = patchDescriptors(M, pm, half);
        S = dm * df.';                                      % normalised cross-correlation matrix
        % mutual best match with Lowe-style ratio test on the correlation score
        nm = size(S,1);
        [best, jf] = max(S, [], 2);                         % best fixed point for every moving point
        [~, im] = max(S, [], 1);                            % best moving point for every fixed point
        back = im(jf);  back = back(:);
        S2 = S;  S2(sub2ind(size(S), (1:nm).', jf)) = -Inf;
        second = max(S2, [], 2);
        good = find(back == (1:nm).' & best > 0.8 & (1 - best) < 0.8 * (1 - second));
        src = pm(good, 1:2);  dst = pf(jf(good), 1:2);
        info.matches = numel(good);
        if numel(good) < 3
            T = eye(3);  info.inliers = 0;
        else
            [T, inl] = ransacAffine(src, dst, 1500, 3);
            info.inliers = nnz(inl);
        end
    otherwise
        error('registerImages:method', 'Unknown method "%s".', method);
end
registered = warpImage(moving, T, [size(fixed,1) size(fixed,2)], 'bilinear', 'reverse');
end

function D = patchDescriptors(G, pts, half)
% Zero-mean, unit-norm (2*half+1)^2 patches around each point -> rows.
n = size(pts,1);
D = zeros(n, (2*half+1)^2);
for k = 1:n
    x = round(pts(k,1));  y = round(pts(k,2));
    p = G(y-half:y+half, x-half:x+half);
    p = p(:).' - mean(p(:));
    D(k,:) = p / max(norm(p), eps);
end
end

function [T, bestInl] = ransacAffine(src, dst, nIter, thr)
% RANSAC estimate of the affine transform src -> dst.
n = size(src,1);
bestInl = false(n,1);
for it = 1:nIter
    idx = randperm(n, 3);
    A = [src(idx,:), ones(3,1)];
    if abs(det(A)) < 1e-6, continue; end
    P = A \ dst(idx,:);                                    % 3x2 affine parameters
    err = sqrt(sum(([src, ones(n,1)] * P - dst).^2, 2));
    inl = err < thr;
    if nnz(inl) > nnz(bestInl), bestInl = inl; end
end
if nnz(bestInl) >= 3                                       % least-squares refit on all inliers
    P = [src(bestInl,:), ones(nnz(bestInl),1)] \ dst(bestInl,:);
    T = [P.'; 0 0 1];
else
    T = eye(3);
end
end
