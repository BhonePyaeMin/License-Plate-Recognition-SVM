function model = svmTrain(X, labels, varargin)
%SVMTRAIN  Multi-class SVM (one-vs-one) built from binary SMO classifiers.
%   model = SVMTRAIN(X, labels, 'Name', value, ...)
%   X      : n x d feature matrix,  labels : n x 1 numeric class ids
%   Options: 'C' (box constraint, default 10)
%            'Kernel' ('rbf' default | 'linear' | 'poly')
%            'Gamma'  (RBF width, default 'scale' = 1/(d*var(X(:))))
%            'Tol' (1e-3)  'MaxIter' (20000)  'Verbose' (false)
%
%   For K classes K*(K-1)/2 binary SVMs are trained, each on the samples of its
%   two classes only (small kernel matrices, fast). Prediction is by voting.
%   Support vectors are stored once and shared by all binary machines.

p = inputParser;
p.addParameter('C', 10);
p.addParameter('Kernel', 'rbf');
p.addParameter('Gamma', 'scale');
p.addParameter('Tol', 1e-3);
p.addParameter('MaxIter', 20000);
p.addParameter('Verbose', false);
p.parse(varargin{:});
o = p.Results;

labels = labels(:);
classes = unique(labels);
nc = numel(classes);
d = size(X, 2);
kp.type = o.Kernel;
if ischar(o.Gamma) || isstring(o.Gamma)
    kp.gamma = 1 / (d * max(var(X(:)), eps));
else
    kp.gamma = o.Gamma;
end

pairs = nchoosek(1:nc, 2);
nP = size(pairs, 1);
machines = cell(nP, 1);
svUnion = false(size(X, 1), 1);
t0 = tic;
for k = 1:nP
    ci = pairs(k,1);  cj = pairs(k,2);
    idx = find(labels == classes(ci) | labels == classes(cj));
    y = ones(numel(idx), 1);
    y(labels(idx) == classes(cj)) = -1;
    m = svmTrainBinary(X(idx,:), y, o.C, kp, o.Tol, o.MaxIter);
    m.globalIdx = idx(m.idx);                    % support vectors as indices into X
    machines{k} = m;
    svUnion(m.globalIdx) = true;
    if o.Verbose && (mod(k, 50) == 0 || k == nP)
        fprintf('  trained %d/%d binary SVMs (%.1fs)\n', k, nP, toc(t0));
    end
end

% shared support-vector matrix; every machine keeps column indices into it
svIdx = find(svUnion);
map = zeros(size(X, 1), 1);
map(svIdx) = 1:numel(svIdx);
for k = 1:nP
    machines{k}.cols = map(machines{k}.globalIdx);
    machines{k} = rmfield(machines{k}, {'idx', 'globalIdx'});
end

model.classes = classes;
model.pairs = pairs;
model.machines = machines;
model.SV = X(svIdx, :);
model.kernel = kp;
model.C = o.C;
model.nTrain = size(X, 1);
end
