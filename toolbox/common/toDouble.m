function I = toDouble(I)
%TODOUBLE  Convert an image of any numeric class to double in the range [0,1].
%   I = TODOUBLE(I) maps uint8 (0..255) and uint16 (0..65535) to [0,1];
%   logical becomes 0/1. A double array is assumed to already be in [0,1]; it is
%   only divided by 255 when its maximum is clearly above 1.5 (a 0..255 image),
%   so a small overshoot caused by noise or sharpening is not mistaken for that.

switch class(I)
    case 'uint8',   I = double(I) / 255;
    case 'uint16',  I = double(I) / 65535;
    case 'logical', I = double(I);
    otherwise
        I = double(I);
        if ~isempty(I) && max(I(:)) > 1.5, I = I / 255; end
end
end
