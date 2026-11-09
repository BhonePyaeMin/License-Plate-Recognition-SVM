function d = editDistance(a, b)
%EDITDISTANCE  Levenshtein distance between two character vectors.
%   d = EDITDISTANCE(a, b) is the minimum number of insertions, deletions and
%   substitutions that turn a into b. Used to score plate readings.

la = numel(a);  lb = numel(b);
D = zeros(la + 1, lb + 1);
D(:,1) = 0:la;  D(1,:) = 0:lb;
for i = 1:la
    for j = 1:lb
        D(i+1, j+1) = min([D(i, j+1) + 1, D(i+1, j) + 1, D(i, j) + (a(i) ~= b(j))]);
    end
end
d = D(la + 1, lb + 1);
end
