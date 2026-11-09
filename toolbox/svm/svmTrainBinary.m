function m = svmTrainBinary(X, y, C, kp, tol, maxIter)
%SVMTRAINBINARY  Soft-margin binary SVM trained with Sequential Minimal Optimisation.
%   m = SVMTRAINBINARY(X, y, C, kp, tol, maxIter)
%   X : n x d training samples, y : n x 1 labels (+1 / -1)
%   C : box constraint, kp : kernel parameters (see KERNELMATRIX)
%   tol : stopping tolerance on the KKT violation (default 1e-3)
%   maxIter : maximum number of pair updates (default 20000)
%
%   Solves   max_a  sum(a) - 1/2 sum_ij a_i a_j y_i y_j K(x_i,x_j)
%            s.t.   0 <= a_i <= C,  sum_i a_i y_i = 0
%   SMO repeatedly picks the "maximal violating" pair (i,j), solves the
%   two-variable sub-problem analytically (Platt, 1998) and clips to the box.
%   j is chosen with the second-order rule of Fan, Chen & Lin (LIBSVM).
%
%   Output m: .idx   indices of the support vectors in X
%             .coef  a_i*y_i of the support vectors
%             .b     bias,   decision f(x) = sum coef_i*K(sv_i,x) + b
%             .nIter iterations used

if nargin < 5 || isempty(tol),     tol = 1e-3; end
if nargin < 6 || isempty(maxIter), maxIter = 20000; end
y = y(:);
n = numel(y);
K = kernelMatrix(X, X, kp);
Kd = diag(K);
a = zeros(n, 1);
F = -y;                                   % F_t = sum_s a_s y_s K(s,t) - y_t  (= error without bias)
tau = 1e-12;
eps0 = 1e-12;
Gmax = 0;  Gmin = 0;

it = 0;
for it = 1:maxIter
    s = -F;
    up  = (y ==  1 & a < C - eps0) | (y == -1 & a > eps0);
    low = (y ==  1 & a > eps0)     | (y == -1 & a < C - eps0);
    sUp = s;   sUp(~up)  = -Inf;   [Gmax, i] = max(sUp);
    sLo = s;   sLo(~low) =  Inf;   Gmin = min(sLo);
    if Gmax - Gmin < tol, break; end               % KKT conditions satisfied

    % second-order working-set selection of the partner j
    bvec = Gmax - s;
    avec = K(i,i) + Kd - 2 * y(i) * (y .* K(:,i));
    avec(avec <= 0) = tau;
    score = -Inf(n, 1);
    cand = low & bvec > 0;
    score(cand) = bvec(cand).^2 ./ avec(cand);
    [~, j] = max(score);
    if ~isfinite(score(j)), break; end

    % analytic solution of the two-variable problem
    ai = a(i);  aj = a(j);
    if y(i) ~= y(j)
        Lb = max(0, aj - ai);      Hb = min(C, C + aj - ai);
    else
        Lb = max(0, ai + aj - C);  Hb = min(C, ai + aj);
    end
    eta = K(i,i) + K(j,j) - 2 * K(i,j);
    if eta <= 0, eta = tau; end
    ajNew = min(max(aj + y(j) * (F(i) - F(j)) / eta, Lb), Hb);
    aiNew = ai + y(i) * y(j) * (aj - ajNew);
    aiNew = min(max(aiNew, 0), C);

    a(i) = aiNew;  a(j) = ajNew;
    F = F + (aiNew - ai) * y(i) * K(:,i) + (ajNew - aj) * y(j) * K(:,j);
end

% bias from the free support vectors (0 < a < C), where f(x_t) = y_t
free = a > 1e-8 & a < C - 1e-8;
if any(free)
    b = mean(-F(free));
else
    b = (Gmax + Gmin) / 2;
end
sv = a > 1e-8;
m.idx = find(sv);
m.coef = a(sv) .* y(sv);
m.b = b;
m.nIter = it;
end
