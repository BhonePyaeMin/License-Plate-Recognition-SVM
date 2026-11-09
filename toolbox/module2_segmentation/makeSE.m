function SE = makeSE(type, sz, angle)
%MAKESE  Create a flat structuring element (logical matrix).
%   SE = MAKESE('rect', [h w])    rectangle of h rows and w columns
%   SE = MAKESE('square', n)      n x n square
%   SE = MAKESE('disk', r)        disc of radius r
%   SE = MAKESE('diamond', r)     city-block ball of radius r
%   SE = MAKESE('cross', n)       plus sign of arm length floor(n/2)
%   SE = MAKESE('line', len, deg) straight line of length len at angle deg

switch lower(type)
    case 'rect'
        SE = true(sz(1), sz(2));
    case 'square'
        SE = true(sz(1));
    case 'disk'
        r = sz(1);
        [x, y] = meshgrid(-r:r, -r:r);
        SE = (x.^2 + y.^2) <= r^2 + 0.5;
    case 'diamond'
        r = sz(1);
        [x, y] = meshgrid(-r:r, -r:r);
        SE = (abs(x) + abs(y)) <= r;
    case 'cross'
        n = sz(1);  c = ceil(n/2);
        SE = false(n);  SE(c,:) = true;  SE(:,c) = true;
    case 'line'
        if nargin < 3, angle = 0; end
        len = sz(1);  r = ceil(len/2);
        SE = false(2*r+1);
        t = linspace(-(len-1)/2, (len-1)/2, 4*len);
        x = round(r + 1 + t*cosd(angle));
        y = round(r + 1 - t*sind(angle));
        SE(sub2ind(size(SE), y, x)) = true;
        rows = any(SE, 2);  cols = any(SE, 1);
        SE = SE(rows, cols);
    otherwise
        error('makeSE:type', 'Unknown structuring element "%s".', type);
end
end
