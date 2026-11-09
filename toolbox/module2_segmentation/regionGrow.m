function [BW, nIter] = regionGrow(I, seed, tol, conn)
%REGIONGROW  Region-growing segmentation from one or more seed points.
%   [BW, nIter] = REGIONGROW(I, seed, tol, conn)
%   seed : k x 2 matrix of [row col] seed positions
%   tol  : maximum absolute gray-level difference to the seed mean (default 0.1)
%   conn : 4 or 8 neighbourhood (default 8)
%
%   Starting from the seeds, a pixel is added when it touches the current region
%   and |I - mean seed intensity| <= tol. The loop stops when no pixel is added.

if nargin < 3 || isempty(tol),  tol = 0.1; end
if nargin < 4 || isempty(conn), conn = 8; end
I = toGray(I);
[h, w] = size(I);
seed = round(seed);
seed(:,1) = min(max(seed(:,1), 1), h);
seed(:,2) = min(max(seed(:,2), 1), w);

% reference intensity = mean of 3x3 neighbourhoods around the seeds
vals = zeros(size(seed,1), 1);
for k = 1:size(seed,1)
    r = max(seed(k,1)-1,1):min(seed(k,1)+1,h);
    c = max(seed(k,2)-1,1):min(seed(k,2)+1,w);
    vals(k) = mean(mean(I(r, c)));
end
ref = mean(vals);
candidate = abs(I - ref) <= tol;

BW = false(h, w);
BW(sub2ind([h w], seed(:,1), seed(:,2))) = true;
if conn == 4, N = [0 1 0; 1 1 1; 0 1 0]; else, N = ones(3); end

nIter = 0;
while true
    grown = (conv2(double(BW), N, 'same') > 0) & candidate;
    grown = grown | BW;
    nIter = nIter + 1;
    if nnz(grown) == nnz(BW), break; end
    BW = grown;
end
end
