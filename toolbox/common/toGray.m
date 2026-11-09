function G = toGray(I)
%TOGRAY  Convert an RGB (or grayscale) image to a grayscale double image in [0,1].
%   Uses the ITU-R BT.601 luma weights  Y = 0.299 R + 0.587 G + 0.114 B.

I = toDouble(I);
if ndims(I) == 3 && size(I,3) >= 3
    G = 0.299*I(:,:,1) + 0.587*I(:,:,2) + 0.114*I(:,:,3);
else
    G = I(:,:,1);
end
end
