function J = histEqualize(I, nLevels)
%HISTEQUALIZE  Histogram equalisation (Module 1 - histogram processing).
%   J = HISTEQUALIZE(I) spreads the gray levels of I so the output histogram is
%   approximately flat. The mapping is the normalised cumulative histogram:
%       s_k = (cdf(r_k) - cdf_min) / (1 - cdf_min)
%   For RGB images only the V (brightness) channel of HSV is equalised so the
%   colours are not distorted.

if nargin < 2, nLevels = 256; end
I = toDouble(I);
if size(I,3) == 3
    hsv = rgb2hsv(I);
    hsv(:,:,3) = histEqualize(hsv(:,:,3), nLevels);
    J = hsv2rgb(hsv);
    return
end
q = min(floor(I * nLevels), nLevels - 1) + 1;          % quantise to 1..L
h = accumarray(q(:), 1, [nLevels 1]);                   % histogram
cdf = cumsum(h) / numel(q);                             % cumulative distribution
cdfMin = cdf(find(h > 0, 1));
map = (cdf - cdfMin) / (1 - cdfMin + eps);              % equalisation transfer function
map = min(max(map, 0), 1);
J = reshape(map(q), size(I));
end
