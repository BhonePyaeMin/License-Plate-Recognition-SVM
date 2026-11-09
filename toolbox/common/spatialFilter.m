function J = spatialFilter(I, K, padMode)
%SPATIALFILTER  Correlate an image with an odd-sized kernel (like imfilter).
%   J = SPATIALFILTER(I, K) filters every channel of I with kernel K using
%   replicated borders. J = SPATIALFILTER(I, K, padMode) selects the border
%   handling ('replicate' | 'symmetric' | 'zero').
%
%   Correlation is used (the kernel is not flipped), so J(x) = sum K(k)*I(x+k).

if nargin < 3, padMode = 'replicate'; end
[kr, kc] = size(K);
if mod(kr,2) == 0 || mod(kc,2) == 0
    error('spatialFilter:kernel', 'Kernel dimensions must be odd.');
end
I = double(I);
P = padImage(I, (kr-1)/2, (kc-1)/2, padMode);
J = zeros(size(I));
for ch = 1:size(I,3)
    J(:,:,ch) = conv2(P(:,:,ch), rot90(K,2), 'valid');
end
end
