function J = radialDistortion(I, k1, k2, mode, method)
%RADIALDISTORTION  Apply or correct radial (barrel / pincushion) lens distortion.
%   J = RADIALDISTORTION(I, k1, k2, 'correct', method)  - undistort a photo
%   J = RADIALDISTORTION(I, k1, k2, 'apply',   method)  - simulate the distortion
%
%   Brown model on normalised coordinates (centre = 0, corner radius = 1):
%       x_d = x_u * (1 + k1*r_u^2 + k2*r_u^4),   r_u^2 = x_u^2 + y_u^2
%   k1 < 0 : barrel distortion, k1 > 0 : pincushion distortion (in this model).
%   'correct' uses reverse mapping directly: for each undistorted output pixel
%   the distorted source position is computed and interpolated.
%   'apply' needs the inverse of the model: for every distorted radius r_d the
%   radius r_u with r_u*(1 + k1*r_u^2 + k2*r_u^4) = r_d is found by Newton's method.
%   For strong barrel distortion the model has a largest reachable r_d (for k1 = -0.3
%   it is about 0.70); pixels beyond it have no source point and are left black.

if nargin < 3 || isempty(k2), k2 = 0; end
if nargin < 4, mode = 'correct'; end
if nargin < 5, method = 'bilinear'; end
I = toDouble(I);
[h, w, ~] = size(I);
cx = (w + 1) / 2;  cy = (h + 1) / 2;
f = sqrt(cx^2 + cy^2);                                   % normalisation radius (pixels)
[xo, yo] = meshgrid(1:w, 1:h);
xn = (xo - cx) / f;  yn = (yo - cy) / f;                 % normalised output coordinates

switch lower(mode)
    case 'correct'
        % output pixel is an undistorted point; find where it came from in the photo
        r2 = xn.^2 + yn.^2;
        s = 1 + k1*r2 + k2*r2.^2;
        xs = xn .* s;  ys = yn .* s;
    case 'apply'
        % output pixel is a distorted point with radius rd; solve ru*(1+k1*ru^2+k2*ru^4) = rd
        rd = hypot(xn, yn);
        ru = rd;                                             % start on the inner branch
        for it = 1:30
            g  = ru .* (1 + k1*ru.^2 + k2*ru.^4) - rd;
            dg = 1 + 3*k1*ru.^2 + 5*k2*ru.^4;
            step = g ./ dg;
            step(~isfinite(step)) = 0;
            ru = max(ru - step, 0);
        end
        g = ru .* (1 + k1*ru.^2 + k2*ru.^4) - rd;
        valid = abs(g) < 1e-6;                               % false where no inverse exists
        scale = ones(size(rd));
        nz = rd > 0;
        scale(nz) = ru(nz) ./ rd(nz);
        xs = xn .* scale;  ys = yn .* scale;
        xs(~valid) = -1e6;  ys(~valid) = -1e6;               % far outside the source: left black
    otherwise
        error('radialDistortion:mode', 'Mode must be "correct" or "apply".');
end
J = interpSample(I, xs * f + cx, ys * f + cy, method, 0);
J = min(max(J, 0), 1);
end
