function J = bilateralFilter(I, sigmaS, sigmaR, pad)
%BILATERALFILTER  Edge-preserving smoothing (Module 1 - non-linear spatial filter).
%   J = BILATERALFILTER(I, sigmaS, sigmaR, pad)
%   Every pixel becomes the weighted mean of its neighbours. The weight of a neighbour is the product of
%     - a spatial Gaussian of the distance (sigmaS pixels), like an ordinary Gaussian filter, and
%     - a range Gaussian of the grey-level difference (sigmaR, as a fraction of the grey range of the photo:
%       the 1 % .. 99 % luminance spread, so a dark photo whose levels all lie between 0 and 0.2 gets a
%       proportionally smaller sigma; with a fixed sigma of 0.15 such a photo is smoothed like by a Gaussian
%       filter and the strokes are blurred: on simulated dark night photos that cost 2 of 16 plates).
%   Neighbours on the other side of an edge differ strongly in grey level, get a tiny weight and are not
%   mixed in: noise is smoothed but the edges of the characters stay sharp (a Gaussian filter blurs them).
%   For colour images the range weights are taken from the luminance and applied to all channels.
%   sigmaS default 1.5 (window radius ceil(2*sigmaS), at most 4 = 9 x 9), sigmaR default 0.15,
%   pad = border handling 'replicate' (default) | 'symmetric' | 'zero' (see PADIMAGE).

if nargin < 2 || isempty(sigmaS), sigmaS = 1.5; end
if nargin < 3 || isempty(sigmaR), sigmaR = 0.15; end
if nargin < 4 || isempty(pad), pad = 'replicate'; end
I = toDouble(I);
[h, w, nc] = size(I);
r = min(max(ceil(2 * sigmaS), 1), 4);
G = toGray(I);
v = sort(G(:));
spread = v(max(1, round(0.99 * numel(v)))) - v(max(1, round(0.01 * numel(v))));
sigmaR = sigmaR * min(1, max(spread, 0.05));                     % relative to the grey range (never above the nominal value)
P = padImage(I, r, r, pad);
PG = padImage(G, r, r, pad);
num = zeros(h, w, nc);  den = zeros(h, w);
for dy = -r:r
    for dx = -r:r
        ws = exp(-(dx^2 + dy^2) / (2 * sigmaS^2));
        rows = r + 1 + dy + (0:h-1);  cols = r + 1 + dx + (0:w-1);
        wgt = ws * exp(-((PG(rows, cols) - G).^2) / (2 * sigmaR^2));
        den = den + wgt;
        for ch = 1:nc
            num(:,:,ch) = num(:,:,ch) + wgt .* P(rows, cols, ch);
        end
    end
end
J = num ./ den;
end
