function P = padImage(I, pr, pc, mode, val)
%PADIMAGE  Pad an image by pr rows and pc columns on every side.
%   P = PADIMAGE(I, pr, pc, mode, val)
%   mode : 'replicate' (default) | 'symmetric' | 'zero' | 'constant' (uses val)
%   Works for gray (HxW) and multi-channel (HxWxC) arrays of any class.

if nargin < 4, mode = 'replicate'; end
if nargin < 5, val = 0; end
[r, c, ~] = size(I);
ri = (1-pr):(r+pr);
ci = (1-pc):(c+pc);
switch mode
    case 'replicate'
        P = I(min(max(ri,1),r), min(max(ci,1),c), :);
    case 'symmetric'
        P = I(mirrorIndex(ri, r), mirrorIndex(ci, c), :);
    case {'zero', 'constant'}
        if strcmp(mode, 'zero'), val = 0; end
        P = repmat(cast(val, 'like', I), r + 2*pr, c + 2*pc, size(I,3));
        P(pr+1:pr+r, pc+1:pc+c, :) = I;
    otherwise
        error('padImage:mode', 'Unknown padding mode "%s".', mode);
end
end

function k = mirrorIndex(i, n)
% Reflect out-of-range 1-based indices back into 1..n (symmetric extension).
k = mod(i - 1, 2*n);
m = k >= n;
k(m) = 2*n - 1 - k(m);
k = k + 1;
end
