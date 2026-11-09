function [ok, s] = charsLookValid(cv, chars)
%CHARSLOOKVALID  Do the segmented components look like the characters of a plate (not like streaks, blobs)?
%   [ok, s] = CHARSLOOKVALID(cv, chars) with cv from TRAINCHARVALIDMODEL (struct with the fields svm and
%   rule) and chars a cell array of 32x32 images. s = CHARVALIDITY scores.
%   Rule (cv.rule): the mean score is above rule.minMean (default 0.2) and at least the share rule.minShare
%   (default 0.6) of the components has a positive score. The rule was chosen by looking at the scores of
%   13 correctly read plates (all kept) and 43 non-plate regions (37 rejected) of the 16 test photos:
%   a small sample, see the README.
if isempty(cv) || isempty(chars), ok = true;  s = zeros(numel(chars), 1);  return; end
rule = struct('minMean', 0.2, 'minShare', 0.6);
if isfield(cv, 'rule'), rule = cv.rule; end
s = charValidity(cv, chars);
ok = mean(s) > rule.minMean && mean(s > 0) >= rule.minShare;
end
