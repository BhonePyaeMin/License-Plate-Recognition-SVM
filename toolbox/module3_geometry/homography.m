function [H, err] = homography(src, dst)
%HOMOGRAPHY  3x3 projective transform from point pairs (direct linear transform, SVD).
%   [H, err] = HOMOGRAPHY(src, dst)
%   src, dst : n x 2 matrices of corresponding points [x y], n >= 4 (x = column, y = row).
%   H        : 3x3 matrix with  [u; v; w] = H * [x; y; 1]  and  dst = [u/w, v/w]; it can be passed to
%              WARPIMAGE as the transform T (input coordinates -> output coordinates).
%   err      : root-mean-square distance between H*src and dst (0 for 4 exact pairs).
%
%   Every pair gives two linear equations in the nine entries of H (A*h = 0). The solution is the right
%   singular vector of A that belongs to the smallest singular value. The points are first translated to
%   their centroid and scaled to a mean distance of sqrt(2) (Hartley normalisation), otherwise pixel
%   coordinates of several hundred make A badly conditioned.
%   With n > 4 pairs it is the least-squares solution; the four corners of a plate quadrilateral and the
%   corners of the 240 x 80 target rectangle give the perspective correction used by RECTIFYPLATE.

n = size(src, 1);
if size(src, 2) ~= 2 || ~isequal(size(src), size(dst)) || n < 4
    error('homography:input', 'src and dst must be n x 2 with n >= 4 and the same size.');
end
[Ts, s] = normalisePoints(src);
[Td, d] = normalisePoints(dst);
A = zeros(2 * n, 9);
for k = 1:n
    x = s(k, 1);  y = s(k, 2);  u = d(k, 1);  v = d(k, 2);
    A(2*k-1, :) = [-x, -y, -1,  0,  0,  0, u*x, u*y, u];
    A(2*k,   :) = [ 0,  0,  0, -x, -y, -1, v*x, v*y, v];
end
[~, ~, V] = svd(A);
Hn = reshape(V(:, end), 3, 3).';                               % row-major -> 3x3
H = Td \ Hn * Ts;                                              % undo the normalisation
H = H / H(3, 3);
if nargout > 1
    P = H * [src.'; ones(1, n)];
    err = sqrt(mean(sum((P(1:2, :) ./ P(3, :) - dst.').^2, 1)));
end
end

function [T, P] = normalisePoints(P0)
c = mean(P0, 1);
dist = mean(hypot(P0(:, 1) - c(1), P0(:, 2) - c(2)));
s = sqrt(2) / max(dist, eps);
T = [s 0 -s * c(1); 0 s -s * c(2); 0 0 1];
Q = T * [P0.'; ones(1, size(P0, 1))];
P = Q(1:2, :).';
end
