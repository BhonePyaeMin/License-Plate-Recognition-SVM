function s = plateScore(pm, crop)
%PLATESCORE  SVM decision value of a candidate region (> 0: looks like a plate).
%   s = PLATESCORE(pm, crop) with pm from TRAINPLATEMODEL. For several crops pass a
%   cell array of images; s is then a vector.

if iscell(crop)
    s = zeros(numel(crop), 1);
    for k = 1:numel(crop), s(k) = plateScore(pm, crop{k}); end
    return
end
f = plateFeatures(crop);
K = kernelMatrix(f, pm.svm.SV, pm.svm.kernel);
s = K * pm.svm.coef + pm.svm.b;
end
