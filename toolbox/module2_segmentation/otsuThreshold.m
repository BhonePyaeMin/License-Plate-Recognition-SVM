function [level, BW, eta] = otsuThreshold(I)
%OTSUTHRESHOLD  Otsu's global threshold (maximises between-class variance).
%   [level, BW, eta] = OTSUTHRESHOLD(I)
%   level : threshold in [0,1]; pixels >= level are foreground
%   BW    : binary image  I >= level
%   eta   : separability measure in [0,1] (1 = perfectly bimodal)
%
%   Theory: for threshold k the class probabilities are w0(k), w1(k) = 1-w0(k) and
%   the class means mu0(k), mu1(k). Otsu picks k maximising
%       sigma_B^2(k) = (mu_T*w0(k) - mu(k))^2 / (w0(k)*(1-w0(k))).

I = toGray(I);
L = 256;
q = min(floor(I * L), L - 1) + 1;
p = accumarray(q(:), 1, [L 1]) / numel(q);
w0 = cumsum(p);
mu = cumsum(p .* (1:L)');
muT = mu(end);
sb = (muT * w0 - mu).^2 ./ (w0 .* (1 - w0));
sb(~isfinite(sb)) = 0;
[sbMax, k] = max(sb);
% if several equal maxima exist, use the middle one
k = round(mean(find(sb >= sbMax - 1e-12)));
level = k / L;
varT = sum(((1:L)' - muT).^2 .* p);
eta = sbMax / max(varT, eps);
BW = I >= level;
end
