function [res, box] = marginRetry(srcs, model, box, res, varargin)
%MARGINRETRY  Read a plate again when the first reading looks cut off at one end (the region number "797" of T935AK 797).
%   [res, box] = MARGINRETRY(srcs, model, box, res, 'Name', value, ...)
%   srcs : the photo in which the plate was cut out, or a cell array of versions of it (the version of the search, the original), all of
%          the same size; box : [x y w h] of the plate; res : the reading from RECOGNIZEPLATE of that crop.
%   Two things lose characters at the end of a plate, and both showed on a night photo of a Mini (T935AK 797 was read T935AK or T935AK7):
%     - a tight box: SEGMENTCHARS drops every component that touches the border of the crop, so the small region number (and the line
%       under it) at the edge is lost; a box that is a little wider (8 % and 16 % of the plate height on every side) keeps it,
%     - the brightened or equalised copy of a dark photo, in which the plate is cut out, may have glare that joins the characters;
%       the same box in the original photo reads them.
%   It is only tried when the reading looks cut off: the segmented row leaves a gap of more than 1.2 character widths at one end of the
%   plate crop (a complete reading of a tight box has no such gap). A new reading is taken only when it is safe:
%     - it holds the old text (T935AK797 holds T935AK7), or the two differ in at most one character at the start or end, and it is longer
%       (at most 10 characters),
%     - every character of it has at least 0.55 of the median character height (specks and frame bits are no characters),
%     - its vote confidence is not more than 0.15 lower than the old one.
%   Options: 'Margins' ([0 0.08 0.16]) in plate heights   'MinChars' (4)   'Split' (true)   'Force' (false: try also when no gap shows)
%   Returns the new reading and its box (wider if a margin was used), or the old ones.

p = inputParser;
p.addParameter('Margins', [0 0.08 0.16]);
p.addParameter('MinChars', 4);
p.addParameter('Split', true);
p.addParameter('Force', false);
p.parse(varargin{:});
o = p.Results;

if ~res.found || isempty(res.text) || numel(res.text) >= 10 || isempty(box), return; end
if ~iscell(srcs), srcs = {srcs}; end
if ~o.Force && ~looksCutOff(res), return; end
t0 = strrep(res.text, ' ', '');  n0 = numel(t0);  c0 = mean(res.conf);
bestKey = -Inf;  best = [];  bestBox = box;
for s = 1:numel(srcs)
    src = toDouble(srcs{s});
    [H, W, ~] = size(src);
    for m = o.Margins(:).'
        if s == 1 && m == 0, continue; end                      % that is the reading we have
        px = 0;  if m > 0, px = max(2, round(m * box(4))); end
        x0 = max(1, floor(box(1)) - px);  x1 = min(W, ceil(box(1) + box(3) - 1) + px);
        y0 = max(1, floor(box(2)) - px);  y1 = min(H, ceil(box(2) + box(4) - 1) + px);
        if x1 - x0 < 20 || y1 - y0 < 8, continue; end
        try
            r = recognizePlate(src, model, 'Plate', src(y0:y1, x0:x1, :), 'Exposure', 'off', 'Split', o.Split, 'MinChars', o.MinChars);
        catch
            continue
        end
        if ~r.found, continue; end
        t1 = strrep(r.text, ' ', '');  n1 = numel(t1);
        if n1 <= n0 || n1 > 10, continue; end
        if ~(contains(t1, t0) || closeTexts(t1, t0)), continue; end
        if mean(r.conf) < c0 - 0.15, continue; end
        if ~isempty(r.boxes) && any(r.boxes(:, 4) < 0.55 * median(r.boxes(:, 4))), continue; end
        key = n1 + mean(r.conf);
        if key > bestKey, bestKey = key;  best = r;  bestBox = [x0, y0, x1 - x0 + 1, y1 - y0 + 1]; end
    end
end
if ~isempty(best)
    best.bbox = bestBox;  best.detectDebug = res.detectDebug;  best.guess = res.guess;     % the new box is in the coordinates of the photo
    res = best;  box = bestBox;
end
end

function yes = looksCutOff(res)
% the segmented row leaves more than 1.2 character widths free at the left or right end of the plate crop
yes = true;                                                      % unknown: try
sd = res.segDebug;
if isempty(sd) || ~isfield(sd, 'plate') || isempty(res.boxes), return; end
bx = res.boxes;
wm = median(bx(:, 3));
gapL = min(bx(:, 1)) - 1;
gapR = size(sd.plate, 2) - max(bx(:, 1) + bx(:, 3));
yes = max(gapL, gapR) > 1.2 * wm;
end

function yes = closeTexts(a, b)
% the shorter text b (old) differs from the start or the end of the longer text a (new) in at most one character
yes = false;
nb = numel(b);
if numel(a) <= nb, return; end
yes = sum(a(1:nb) ~= b) <= 1 || sum(a(end - nb + 1:end) ~= b) <= 1;
end
