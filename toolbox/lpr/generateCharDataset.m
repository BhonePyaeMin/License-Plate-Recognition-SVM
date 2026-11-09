function [X, y, imgs] = generateCharDataset(tpl, variantIdx, nPerClass, seed, signed)
%GENERATECHARDATASET  Synthetic character dataset (HOG features + labels).
%   [X, y, imgs] = GENERATECHARDATASET(tpl, variantIdx, nPerClass, seed)
%   tpl        : glyph templates from BUILDGLYPHTEMPLATES
%   variantIdx : indices of the font variants that may be used
%   nPerClass  : samples per character class (36 classes)
%   seed       : random seed (makes the dataset reproducible)
%   signed     : true: signed-orientation HOG with 18 bins (see HOGFEATURES; default false = 324 values)
%   X : n x 324 HOG features (648 if signed), y : n x 1 class index (1..36 = tpl.chars),
%   imgs : 32x32xn uint8 images of the normalised characters (optional).

if nargin < 4, seed = 1; end
if nargin < 5, signed = false; end
nBins = 9;  if signed, nBins = 18; end
rng(seed);
nC = numel(tpl.chars);
n = nC * nPerClass;
y = zeros(n, 1);
X = [];
if nargout > 2, imgs = zeros(32, 32, n, 'uint8'); end
i = 0;
for k = 1:nPerClass
    for c = 1:nC
        i = i + 1;
        v = variantIdx(randi(numel(variantIdx)));
        N = augmentGlyph(tpl.glyphs{v}{c});
        f = hogFeatures(N, 8, nBins, signed);
        if isempty(X), X = zeros(n, numel(f)); end
        X(i, :) = f;
        y(i) = c;
        if nargout > 2, imgs(:,:,i) = uint8(255 * N); end
    end
end
end
