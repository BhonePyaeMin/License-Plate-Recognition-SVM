function BW = fillHoles(BW)
%FILLHOLES  Fill background regions that are completely surrounded by foreground.
%   A hole is a 4-connected background component that does not touch the border.

BW = logical(BW);
[L, n] = labelComponents(~BW, 4);
if n == 0, return; end
border = unique([L(1,:), L(end,:), L(:,1).', L(:,end).']);
border(border == 0) = [];
isHole = true(n, 1);
isHole(border) = false;
holeMask = false(size(BW));
holeMask(L > 0) = isHole(L(L > 0));
BW = BW | holeMask;
end
