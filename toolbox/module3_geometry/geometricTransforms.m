function varargout = geometricTransforms(I, op, varargin)
%GEOMETRICTRANSFORMS  Translation, scaling, rotation, shear and general affine warps.
%   [J, T] = GEOMETRICTRANSFORMS(I, 'translate', tx, ty, method)
%   [J, T] = GEOMETRICTRANSFORMS(I, 'scale',     sx, sy, method)   zoom about the centre
%   [J, T] = GEOMETRICTRANSFORMS(I, 'rotate',    deg, method, canvas)
%   [J, T] = GEOMETRICTRANSFORMS(I, 'shear',     shx, shy, method)
%   [J, T] = GEOMETRICTRANSFORMS(I, 'affine',    A, method)        A is 2x3 or 3x3
%
%   method : 'nearest' | 'bilinear' (default) | 'bicubic'
%   canvas : 'same' (default, output keeps the input size) | 'full' (rotate only,
%            enlarges the canvas so nothing is cut off)
%   Rotation angles are in degrees, counter-clockwise as seen on screen.
%   All warps use reverse mapping. T maps input to output coordinates.

I = toDouble(I);
[h, w, ~] = size(I);
cx = (w + 1) / 2;  cy = (h + 1) / 2;                      % image centre
Tc  = [1 0 cx; 0 1 cy; 0 0 1];                            % move origin back to centre
Tc0 = [1 0 -cx; 0 1 -cy; 0 0 1];                          % move centre to origin
method = 'bilinear';
outSize = [h w];

switch lower(op)
    case 'translate'
        tx = varargin{1};  ty = varargin{2};
        if numel(varargin) >= 3, method = varargin{3}; end
        T = [1 0 tx; 0 1 ty; 0 0 1];
    case 'scale'
        sx = varargin{1};
        if numel(varargin) >= 2 && ~isempty(varargin{2}), sy = varargin{2}; else, sy = sx; end
        if numel(varargin) >= 3, method = varargin{3}; end
        T = Tc * diag([sx sy 1]) * Tc0;
    case 'rotate'
        a = varargin{1} * pi/180;
        if numel(varargin) >= 2, method = varargin{2}; end
        canvas = 'same';
        if numel(varargin) >= 3, canvas = varargin{3}; end
        R = [cos(a) sin(a) 0; -sin(a) cos(a) 0; 0 0 1];     % y axis points down
        T = Tc * R * Tc0;
        if strcmpi(canvas, 'full')
            outSize = ceil([abs(h*cos(a)) + abs(w*sin(a)), abs(w*cos(a)) + abs(h*sin(a))] - 1e-9);
            T = [1 0 (outSize(2)+1)/2; 0 1 (outSize(1)+1)/2; 0 0 1] * R * Tc0;
        end
    case 'shear'
        shx = varargin{1};  shy = varargin{2};
        if numel(varargin) >= 3, method = varargin{3}; end
        T = Tc * [1 shx 0; shy 1 0; 0 0 1] * Tc0;
    case 'affine'
        A = varargin{1};
        if numel(varargin) >= 2, method = varargin{2}; end
        if size(A,1) == 2, A = [A; 0 0 1]; end
        T = A;
    otherwise
        error('geometricTransforms:op', 'Unknown transformation "%s".', op);
end
J = warpImage(I, T, outSize, method, 'reverse');
varargout{1} = J;
if nargout > 1, varargout{2} = T; end
end
