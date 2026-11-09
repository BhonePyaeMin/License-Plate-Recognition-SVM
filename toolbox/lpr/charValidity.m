function s = charValidity(cv, chars)
%CHARVALIDITY  Score of every character image: > 0 looks like a character, < 0 like a streak or blob.
%   s = CHARVALIDITY(cv, chars) with cv from TRAINCHARVALIDMODEL and chars a cell array of 32x32 images
%   (as SEGMENTCHARS returns them). s is a column vector of SVM decision values.
s = zeros(numel(chars), 1);
if isempty(chars), return; end
X = zeros(numel(chars), 324);
for k = 1:numel(chars), X(k, :) = hogFeatures(chars{k}); end
K = kernelMatrix(X, cv.svm.SV, cv.svm.kernel);
s = K * cv.svm.coef + cv.svm.b;
end
