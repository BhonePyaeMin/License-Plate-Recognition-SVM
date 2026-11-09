function props = componentProps(L, n)
%COMPONENTPROPS  Area, bounding box and centroid of every labelled component.
%   props = COMPONENTPROPS(L, n) where L comes from LABELCOMPONENTS.
%   props.Area        n x 1   number of pixels
%   props.BoundingBox n x 4   [x y width height] (x = first column, y = first row)
%   props.Centroid    n x 2   [x y]
%   props.Extent      n x 1   Area / (width*height)
%   props.Aspect      n x 1   width / height

if nargin < 2, n = max(L(:)); end
props = struct('Area', zeros(n,1), 'BoundingBox', zeros(n,4), 'Centroid', zeros(n,2), ...
               'Extent', zeros(n,1), 'Aspect', zeros(n,1));
if n == 0, return; end
idx = find(L > 0);
lab = L(idx);
[r, c] = ind2sub(size(L), idx);
area = accumarray(lab, 1, [n 1]);
r0 = accumarray(lab, r, [n 1], @min);   r1 = accumarray(lab, r, [n 1], @max);
c0 = accumarray(lab, c, [n 1], @min);   c1 = accumarray(lab, c, [n 1], @max);
props.Area = area;
props.BoundingBox = [c0, r0, c1 - c0 + 1, r1 - r0 + 1];
props.Centroid = [accumarray(lab, c, [n 1]) ./ area, accumarray(lab, r, [n 1]) ./ area];
props.Extent = area ./ (props.BoundingBox(:,3) .* props.BoundingBox(:,4));
props.Aspect = props.BoundingBox(:,3) ./ props.BoundingBox(:,4);
end
