function [BW, keep, props, L] = filterComponents(BW, varargin)
%FILTERCOMPONENTS  Shape-based segmentation: keep only components matching size/shape rules.
%   [BW, keep, props, L] = FILTERCOMPONENTS(BW, 'Name', value, ...)
%   Rules (all optional):
%     'MinArea', 'MaxArea'      area in pixels
%     'MinAspect', 'MaxAspect'  bounding-box width/height
%     'MinExtent'               area / bounding-box area (how rectangular)
%     'MinHeight', 'MaxHeight', 'MinWidth', 'MaxWidth'   bounding-box size in pixels
%     'Conn'                    4 or 8 (default 8)
%   keep is a logical vector over the component labels; props from COMPONENTPROPS.

p = inputParser;
p.addParameter('MinArea', 0);     p.addParameter('MaxArea', Inf);
p.addParameter('MinAspect', 0);   p.addParameter('MaxAspect', Inf);
p.addParameter('MinExtent', 0);
p.addParameter('MinHeight', 0);   p.addParameter('MaxHeight', Inf);
p.addParameter('MinWidth', 0);    p.addParameter('MaxWidth', Inf);
p.addParameter('Conn', 8);
p.parse(varargin{:});
r = p.Results;

[L, n] = labelComponents(BW, r.Conn);
props = componentProps(L, n);
bb = props.BoundingBox;
keep = props.Area >= r.MinArea & props.Area <= r.MaxArea & ...
       props.Aspect >= r.MinAspect & props.Aspect <= r.MaxAspect & ...
       props.Extent >= r.MinExtent & ...
       bb(:,4) >= r.MinHeight & bb(:,4) <= r.MaxHeight & ...
       bb(:,3) >= r.MinWidth  & bb(:,3) <= r.MaxWidth;
BW = false(size(L));
if n > 0
    BW(L > 0) = keep(L(L > 0));
end
end
