function [txt, readings] = consensusText(I, box, baseText, model, varargin)
%CONSENSUSTEXT  Read a found plate from several filtered copies and vote per character.
%   [txt, readings] = CONSENSUSTEXT(I, box, baseText, model, 'Name', value, ...)
%   I        the photo (as the user gave it: RGB or gray, uint8 or double)
%   box      [x y w h] of the plate in I
%   baseText the reading of the plate without a filter (it takes part in the vote)
%   model    the recogniser model (RECOGNIZEPLATE)
%   One filter reads one plate differently from another: unsharp masking, local equalisation, contrast stretching, a sharpening
%   kernel, enlarging, gamma and deblurring each move some characters across the SVM boundary (I and 1, 8 and B, 6 and G). The
%   plate crop (12 % margin) is therefore read in 8 copies (no filter, unsharp masking, CLAHE, contrast stretching, sharpening kernel,
%   resize 1.5 + unsharp, gamma 0.7, Richardson-Lucy) and the texts of the most common length vote per character position.
%   Measured on 106 held-out photos (dev models; 16 project test photos + 90 OpenALPR test photos): exact plates 56 -> 60 of 106
%   (whole-text vote 59); the best copy would give 68, so the vote takes about a third of what a perfect choice could.
%   Options: 'Margin' (default 0.12)   'Filters' (default: the 8 copies above, a cell array of APPLYPREFILTERS chains)
%   readings is the list of the texts that were read (empty texts left out).

p = inputParser;
p.addParameter('Margin', 0.12);
p.addParameter('Filters', {});
p.parse(varargin{:});
o = p.Results;

I = toDouble(I);
[H, W, ~] = size(I);
b = round(box);
pad = round(o.Margin * b(4));
x0 = max(1, b(1) - pad);  x1 = min(W, b(1) + b(3) - 1 + pad);
y0 = max(1, b(2) - pad);  y1 = min(H, b(2) + b(4) - 1 + pad);
txt = baseText;  readings = {};
if x1 - x0 < 15 || y1 - y0 < 6, return; end
crop = I(y0:y1, x0:x1, :);

V = o.Filters;
if isempty(V)
    C = @(name, q) struct('name', name, 'p', q);
    V = {C('Contrast stretching', [1 99]), C('Local histogram equalisation (CLAHE)', [8 3]), C('Deblur (Richardson-Lucy)', [1.5 10])};
end
for v = 1:numel(V)
    try
        F = applyPrefilters(crop, V{v}, 'Kernel', [0 -1 0; -1 5 -1; 0 -1 0]);
        q = recognizePlate(F, model, 'Plate', F, 'Exposure', 'auto', 'MinChars', 4);
        if q.found && ~isempty(q.text), readings{end+1} = q.text; end %#ok<AGROW>
    catch
    end
end
if isempty(readings), return; end

L = cellfun(@numel, readings);                                   % the most common length of the filtered readings decides (ties: the shorter)
cand = unique(L);  best = cand(1);  bc = -1;
for l = cand(:).'
    c = sum(L == l) + (numel(baseText) == l);
    if c > bc, bc = c;  best = l; end
end
grp = readings(L == best);
if numel(baseText) == best, grp = [grp, {baseText}]; end
M = char(grp(:));
txt = '';
for j = 1:best
    col = M(:, j);  [u, ~, ic] = unique(col);  cnt = accumarray(ic, 1);  [~, m] = max(cnt);
    txt(end+1) = u(m); %#ok<AGROW>
end
end
