function J = addNoise(I, type, amount)
%ADDNOISE  Add synthetic noise so the denoising filters can be evaluated.
%   J = ADDNOISE(I, type, amount)
%   type   : 'gaussian'   - zero-mean Gaussian, std = amount (default 0.05)
%            'saltpepper' - fraction `amount` of pixels set to 0 or 1 (default 0.05)
%            'speckle'    - multiplicative noise  J = I + I*N(0,amount)

if nargin < 3 || isempty(amount), amount = 0.05; end
I = toDouble(I);
switch lower(type)
    case 'gaussian'
        J = I + amount * randn(size(I));
    case 'saltpepper'
        r = rand(size(I(:,:,1)));
        r = repmat(r, [1 1 size(I,3)]);
        J = I;
        J(r < amount/2) = 0;
        J(r >= amount/2 & r < amount) = 1;
    case 'speckle'
        J = I + I .* (amount * randn(size(I)));
    otherwise
        error('addNoise:type', 'Unknown noise type "%s".', type);
end
J = min(max(J, 0), 1);
end
