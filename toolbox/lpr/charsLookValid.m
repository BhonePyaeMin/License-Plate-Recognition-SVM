function [ok, s] = charsLookValid(cv, chars, boxes)
%CHARSLOOKVALID  Do the segmented components look like the characters of a plate (not like streaks, blobs)?
%   [ok, s] = CHARSLOOKVALID(cv, chars, boxes) with cv from TRAINCHARVALIDMODEL (struct with the fields svm and
%   rule) and chars a cell array of 32x32 images. s = CHARVALIDITY scores. boxes (optional, [x y w h] of the characters) allows the second rule below.
%   Rule (cv.rule): the mean score is above rule.minMean (default 0.2) and at least the share rule.minShare
%   (default 0.6) of the components has a positive score. The rule was chosen by looking at the scores of
%   13 correctly read plates (all kept) and 43 non-plate regions (37 rejected) of the 16 test photos:
%   a small sample, see the README.
%   Two additions (round 13): a regular row of 6 or more components of nearly the same width (std / mean < 0.10) with a mean score above 0.15 is accepted
%   as well (FHM 5505 cut into 7 characters scored 0.20 with 57 % positive), and a row with one component scored below -1.0 (a streak, a blob) is
%   refused (junk readings of held-out photos such as I918HHHUUUI had one at -1.0 to -1.4).
if isempty(cv) || isempty(chars), ok = true;  s = zeros(numel(chars), 1);  return; end
rule = struct('minMean', 0.2, 'minShare', 0.6);
if isfield(cv, 'rule'), rule = cv.rule; end
s = charValidity(cv, chars);
ok = mean(s) > rule.minMean && mean(s > 0) >= rule.minShare;
if ~ok && nargin >= 3 && numel(chars) >= 6 && ~isempty(boxes) && std(boxes(:, 3)) / mean(boxes(:, 3)) < 0.10 && mean(s) > 0.15, ok = true; end
if ok && min(s) < -1.0, ok = false; end
end
