function [pred, conf, votes, score] = svmPredict(model, X)
%SVMPREDICT  Classify rows of X with a model from SVMTRAIN (one-vs-one voting).
%   [pred, conf, votes, score] = SVMPREDICT(model, X)
%   pred  : n x 1 predicted class ids
%   conf  : n x 1 confidence in [0,1] = share of the (K-1) duels won by the winner
%   votes : n x K vote counts
%   score : n x K votes plus a tiny margin term that breaks ties; argmax(score)
%           is the prediction (use it to restrict the decision to some classes)

n = size(X, 1);
nc = numel(model.classes);
Ksv = kernelMatrix(X, model.SV, model.kernel);             % n x (#shared SVs)
votes = zeros(n, nc);
margin = zeros(n, nc);
for k = 1:numel(model.machines)
    m = model.machines{k};
    f = Ksv(:, m.cols) * m.coef + m.b;                     % decision value
    ci = model.pairs(k,1);  cj = model.pairs(k,2);
    win = f > 0;
    votes(win, ci)  = votes(win, ci)  + 1;
    votes(~win, cj) = votes(~win, cj) + 1;
    margin(:, ci) = margin(:, ci) + f;
    margin(:, cj) = margin(:, cj) - f;
end
scale = max(max(abs(margin(:))), eps);                      % margins only break ties between equal vote counts
score = votes + 1e-3 * margin / scale;
[~, best] = max(score, [], 2);
pred = model.classes(best);
conf = votes(sub2ind(size(votes), (1:n).', best)) / (nc - 1);
end
