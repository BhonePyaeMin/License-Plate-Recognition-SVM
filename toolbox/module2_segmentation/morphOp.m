function J = morphOp(I, op, SE)
%MORPHOP  Flat morphological operations for binary and gray-scale images.
%   J = MORPHOP(I, op, SE)
%   op : 'dilate' | 'erode' | 'open' | 'close' | 'gradient' | 'tophat' | 'blackhat'
%   SE : structuring element from MAKESE (default 3x3 square)
%
%   Dilation takes the maximum and erosion the minimum of the image over the
%   structuring element, so the same code handles binary (logical) and
%   gray-scale input. 'open' = erode then dilate (removes small bright objects),
%   'close' = dilate then erode (fills small gaps/holes), 'gradient' = dilate -
%   erode (object outlines), 'tophat' = I - open(I), 'blackhat' = close(I) - I.

if nargin < 3 || isempty(SE), SE = true(3); end
isBin = islogical(I);
A = double(I);
switch lower(op)
    case 'dilate',   J = extremeFilter(A, SE, 'max');
    case 'erode',    J = extremeFilter(A, SE, 'min');
    case 'open',     J = extremeFilter(extremeFilter(A, SE, 'min'), SE, 'max');
    case 'close',    J = extremeFilter(extremeFilter(A, SE, 'max'), SE, 'min');
    case 'gradient', J = extremeFilter(A, SE, 'max') - extremeFilter(A, SE, 'min');
    case 'tophat',   J = A - extremeFilter(extremeFilter(A, SE, 'min'), SE, 'max');
    case 'blackhat', J = extremeFilter(extremeFilter(A, SE, 'max'), SE, 'min') - A;
    otherwise
        error('morphOp:op', 'Unknown morphological operation "%s".', op);
end
if isBin, J = J > 0.5; end
end

function J = extremeFilter(A, SE, mode)
% Maximum (dilation) or minimum (erosion) of A over the structuring element.
SE = logical(SE);
[sr, sc] = size(SE);
cy = floor(sr/2) + 1;  cx = floor(sc/2) + 1;           % SE origin
[h, w] = size(A);
isMax = strcmp(mode, 'max');
if isMax, padVal = -Inf; f = @max; else, padVal = Inf; f = @min; end
P = padImage(A, sr, sc, 'constant', padVal);

if all(SE(:))                                            % rectangle: separable (rows, then columns)
    oy = (1-cy):(sr-cy);  ox = (1-cx):(sc-cx);          % offsets covered by the SE
    if isMax, oy = -oy; ox = -ox; end                    % dilation uses the reflected SE
    acc = P(sr + (1:h) + oy(1), :);
    for k = 2:numel(oy)
        acc = f(acc, P(sr + (1:h) + oy(k), :));          % vertical pass
    end
    J = acc(:, sc + (1:w) + ox(1));
    for k = 2:numel(ox)
        J = f(J, acc(:, sc + (1:w) + ox(k)));            % horizontal pass
    end
else                                                     % general shape: loop over SE pixels
    [ry, rx] = find(SE);
    dy = ry - cy;  dx = rx - cx;
    if isMax, dy = -dy; dx = -dx; end                    % dilation uses the reflected SE
    J = P(sr + (1:h) + dy(1), sc + (1:w) + dx(1));
    for k = 2:numel(dy)
        J = f(J, P(sr + (1:h) + dy(k), sc + (1:w) + dx(k)));
    end
end
end
