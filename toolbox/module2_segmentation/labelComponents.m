function [L, n] = labelComponents(BW, conn)
%LABELCOMPONENTS  Connected-component labelling of a binary image (like bwlabel).
%   [L, n] = LABELCOMPONENTS(BW, conn) returns a label matrix L (0 = background,
%   1..n = components) for 4- or 8-connectivity (default 8).
%
%   Algorithm: the image is first compressed into horizontal runs of foreground
%   pixels; runs that overlap in adjacent rows are merged with a union-find
%   structure, which is much faster than pixel-wise labelling in MATLAB.

if nargin < 2, conn = 8; end
BW = logical(BW);
[h, w] = size(BW);
L = zeros(h, w);
if ~any(BW(:)), n = 0; return; end
e = double(conn == 8);                                  % 1 -> diagonal neighbours touch

% ---- 1. extract runs (row, first column, one-past-last column) in row-major order
d = diff([false(h,1), BW, false(h,1)], 1, 2).';         % (w+1) x h
[cs, rs]  = find(d ==  1);                              % run starts
[ce, ~]   = find(d == -1);                              % run ends (exclusive)
nR = numel(rs);
cnt = accumarray(rs, 1, [h 1]);
first = cumsum(cnt) - cnt + 1;                          % index of first run of every row

% ---- 2. union overlapping runs of consecutive rows
parent = 1:nR;
for r = 2:h
    if cnt(r) == 0 || cnt(r-1) == 0, continue; end
    i = first(r-1);  iEnd = i + cnt(r-1) - 1;
    j = first(r);    jEnd = j + cnt(r) - 1;
    while i <= iEnd && j <= jEnd
        if (ce(i) - 1 >= cs(j) - e) && (cs(i) <= ce(j) - 1 + e)
            [parent, ri] = findRoot(parent, i);
            [parent, rj] = findRoot(parent, j);
            if ri < rj, parent(rj) = ri; elseif rj < ri, parent(ri) = rj; end
        end
        if ce(i) < ce(j), i = i + 1; else, j = j + 1; end
    end
end

% ---- 3. resolve roots, number them consecutively and paint the label image
root = zeros(1, nR);
for k = 1:nR
    [parent, root(k)] = findRoot(parent, k);
end
[~, ~, lab] = unique(root);
n = max(lab);
for k = 1:nR
    L(rs(k), cs(k):ce(k)-1) = lab(k);
end
end

function [parent, r] = findRoot(parent, k)
% Find the root of k with path halving.
while parent(k) ~= k
    parent(k) = parent(parent(k));
    k = parent(k);
end
r = k;
end
