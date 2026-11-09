function BW = colorSegment(I, space, spec)
%COLORSEGMENT  Colour-based segmentation in the RGB or HSV colour space.
%   BW = COLORSEGMENT(I, 'HSV', spec)   or   COLORSEGMENT(I, 'RGB', spec)
%
%   spec can be a preset name  'white' | 'yellow' | 'blue' | 'red' | 'green' | 'black'
%   (HSV only) or a numeric range vector in [0,1]:
%     HSV : [hmin hmax smin smax vmin vmax]   (hmin > hmax wraps around red)
%     RGB : [rmin rmax gmin gmax bmin bmax]
%   Pixels whose three components all fall inside the range are returned as true.
%   Useful for finding white/yellow license-plate backgrounds.

I = toDouble(I);
if size(I,3) == 1, I = repmat(I, [1 1 3]); end
if nargin < 2, space = 'HSV'; end
if ischar(spec) || isstring(spec)
    space = 'HSV';
    switch lower(char(spec))
        case 'white',  spec = [0 1    0 0.25  0.62 1];
        case 'yellow', spec = [0.09 0.20  0.35 1  0.40 1];
        case 'blue',   spec = [0.52 0.72  0.35 1  0.20 1];
        case 'red',    spec = [0.95 0.05  0.45 1  0.25 1];
        case 'green',  spec = [0.22 0.46  0.35 1  0.20 1];
        case 'black',  spec = [0 1    0 1  0 0.22];
        otherwise, error('colorSegment:preset', 'Unknown colour preset "%s".', char(spec));
    end
end
switch upper(space)
    case 'HSV'
        C = rgb2hsv(I);
        H = C(:,:,1);
        if spec(1) <= spec(2)
            mh = H >= spec(1) & H <= spec(2);
        else
            mh = H >= spec(1) | H <= spec(2);               % hue wraps through 0 (red)
        end
        BW = mh & C(:,:,2) >= spec(3) & C(:,:,2) <= spec(4) & ...
                  C(:,:,3) >= spec(5) & C(:,:,3) <= spec(6);
    case 'RGB'
        BW = I(:,:,1) >= spec(1) & I(:,:,1) <= spec(2) & ...
             I(:,:,2) >= spec(3) & I(:,:,2) <= spec(4) & ...
             I(:,:,3) >= spec(5) & I(:,:,3) <= spec(6);
    otherwise
        error('colorSegment:space', 'Colour space must be RGB or HSV.');
end
end
