function [J, detail] = sharpenFilter(I, type, amount)
%SHARPENFILTER  Image sharpening (Module 1 - spatial filtering).
%   [J, detail] = SHARPENFILTER(I, type, amount)
%   type : 'laplacian' - J = I - amount * Laplacian(I)   (8-neighbour kernel)
%          'highpass'  - J = I + amount * (3x3 high-pass response)
%          'unsharp'   - J = I + amount * (I - Gaussian(I))    (high-boost)
%   amount : strength of the sharpening (default 1)
%   detail : the filter response that was added/subtracted (for display)

if nargin < 3 || isempty(amount), amount = 1; end
I = toDouble(I);
switch lower(type)
    case 'laplacian'
        lap = [1 1 1; 1 -8 1; 1 1 1];               % centre coefficient is negative
        detail = spatialFilter(I, lap);
        J = I - amount * detail;
    case 'highpass'
        hp = [-1 -1 -1; -1 8 -1; -1 -1 -1] / 9;     % zero-sum high-pass kernel
        detail = spatialFilter(I, hp);
        J = I + amount * detail * 3;
    case 'unsharp'
        detail = I - spatialFilter(I, gaussianKernel(7, 1.5));
        J = I + amount * detail;
    otherwise
        error('sharpenFilter:type', 'Unknown sharpening filter "%s".', type);
end
J = min(max(J, 0), 1);
end
