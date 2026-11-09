function K = kernelMatrix(A, B, kp)
%KERNELMATRIX  Kernel (Gram) matrix between the rows of A and the rows of B.
%   K = KERNELMATRIX(A, B, kp)
%   kp.type  : 'linear' | 'rbf' | 'poly'
%   kp.gamma : RBF width / polynomial scale
%   kp.degree, kp.coef0 : polynomial kernel parameters (defaults 3 and 1)
%
%   rbf    K(a,b) = exp(-gamma * ||a-b||^2)
%   linear K(a,b) = a'*b
%   poly   K(a,b) = (gamma*a'*b + coef0)^degree

switch lower(kp.type)
    case 'linear'
        K = A * B.';
    case 'rbf'
        D = sum(A.^2, 2) + sum(B.^2, 2).' - 2 * (A * B.');   % squared distances
        K = exp(-kp.gamma * max(D, 0));
    case 'poly'
        if ~isfield(kp, 'degree'), kp.degree = 3; end
        if ~isfield(kp, 'coef0'),  kp.coef0 = 1; end
        K = (kp.gamma * (A * B.') + kp.coef0) .^ kp.degree;
    otherwise
        error('kernelMatrix:type', 'Unknown kernel "%s".', kp.type);
end
end
