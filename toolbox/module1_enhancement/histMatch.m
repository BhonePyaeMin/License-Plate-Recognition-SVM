function J = histMatch(I, ref, nLevels)
%HISTMATCH  Histogram matching / specification (Module 1).
%   J = HISTMATCH(I, ref) transforms I so that its histogram resembles the
%   histogram of the reference image REF. Each input level r is mapped to the
%   smallest reference level z whose CDF is >= the CDF of r.
%   For colour input the V channel of HSV is matched.

if nargin < 3, nLevels = 256; end
I = toDouble(I);  ref = toDouble(ref);
if size(I,3) == 3
    hsv = rgb2hsv(I);
    if size(ref,3) == 3, refV = rgb2hsv(ref); refV = refV(:,:,3); else, refV = ref; end
    hsv(:,:,3) = histMatch(hsv(:,:,3), refV, nLevels);
    J = hsv2rgb(hsv);
    return
end
if size(ref,3) == 3, ref = toGray(ref); end

q  = min(floor(I   * nLevels), nLevels - 1) + 1;
qr = min(floor(ref * nLevels), nLevels - 1) + 1;
cdfI = cumsum(accumarray(q(:),  1, [nLevels 1])) / numel(q);
cdfR = cumsum(accumarray(qr(:), 1, [nLevels 1])) / numel(qr);

map = zeros(nLevels, 1);
j = 1;
for i = 1:nLevels                       % monotone search for the matching level
    while j < nLevels && cdfR(j) < cdfI(i) - 1e-12
        j = j + 1;
    end
    map(i) = (j - 1) / (nLevels - 1);
end
J = reshape(map(q), size(I));
end
