function J = grayTransform(I, method, p1, p2)
%GRAYTRANSFORM  Point (gray-level) transformations for brightness/contrast.
%   J = GRAYTRANSFORM(I, method, p1, p2)
%
%   method    p1                       p2
%   'linear'  contrast gain (def. 1)   brightness offset in [-1,1] (def. 0)
%             J = p1*(I-0.5) + 0.5 + p2
%   'gamma'   gamma (def. 1)           -        J = I.^gamma
%   'log'     a (def. 50)              -        J = log(1+a*I)/log(1+a)
%   'negative' -                       -        J = 1 - I
%   'stretch' low percentile (def. 1)  high percentile (def. 99)
%             linear contrast stretching between the two percentiles
%
%   Colour images are processed per channel (gamma/log/negative/linear) or
%   with common percentiles (stretch).

I = toDouble(I);
if nargin < 3, p1 = []; end
if nargin < 4, p2 = []; end
switch lower(method)
    case 'linear'
        if isempty(p1), p1 = 1; end
        if isempty(p2), p2 = 0; end
        J = p1 * (I - 0.5) + 0.5 + p2;
    case 'gamma'
        if isempty(p1), p1 = 1; end
        J = I .^ p1;
    case 'log'
        if isempty(p1), p1 = 50; end
        J = log(1 + p1 * I) / log(1 + p1);
    case 'negative'
        J = 1 - I;
    case 'stretch'
        if isempty(p1), p1 = 1; end
        if isempty(p2), p2 = 99; end
        v = sort(I(:));
        lo = v(max(1, round(p1/100 * numel(v))));
        hi = v(min(numel(v), max(1, round(p2/100 * numel(v)))));
        if hi <= lo, hi = lo + eps; end
        J = (I - lo) / (hi - lo);
    otherwise
        error('grayTransform:method', 'Unknown method "%s".', method);
end
J = min(max(J, 0), 1);
end
