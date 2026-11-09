function [ok, seg] = isPlateCloseup(img, polarity, segOptions)
%ISPLATECLOSEUP  Is the whole photo a close-up of a licence plate?
%   [ok, seg] = ISPLATECLOSEUP(img, polarity, segOptions)
%   A photo counts as a plate close-up when its width/height is between 1.6 and 9 and the
%   plate characters can be cut out of the WHOLE image in a plausible row (at least 4
%   characters, PLATEROWSCORE >= 0.30). The segmentation searches the tilt (-20..+20 degrees),
%   because a hand-held plate photo is rarely level and the plate frame disturbs the usual
%   tilt estimate. seg holds the segmentation (chars, boxes, dbg) so it need not be repeated.
%   Use polarity 'auto' | 'dark' | 'bright' and segOptions (cell of SEGMENTCHARS options).

if nargin < 2 || isempty(polarity), polarity = 'auto'; end
if nargin < 3, segOptions = {}; end
ok = false;  seg = struct('chars', {{}}, 'boxes', [], 'dbg', []);
ar = size(img, 2) / size(img, 1);
if ar < 1.6 || ar > 9, return; end
[chars, boxes, dbg] = segmentChars(img, 'Polarity', polarity, 'Strategies', {'otsu', 'adaptive'}, ...
                                   'SearchAngle', true, segOptions{:});
seg = struct('chars', {chars}, 'boxes', boxes, 'dbg', dbg);
ok = numel(chars) >= 4 && plateRowScore(boxes) >= 0.30;
end
