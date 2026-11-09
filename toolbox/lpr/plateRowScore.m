function v = plateRowScore(boxes)
%PLATEROWSCORE  How plate-like is a row of segmented characters? (0 = not at all, ~1 = typical plate)
%   v = PLATEROWSCORE(boxes) with boxes = [x y w h] per character, measured in a plate that
%   was resized to a height of 100 pixels (as SEGMENTCHARS returns them).
%   The score is the product of five factors: a plausible number of characters (3..12, best
%   7), similar heights, characters that fill about 55 % of the plate height, regular spacing
%   (the widest gap, a space in the text, is ignored) and centres on one line.

n = size(boxes, 1);
if n < 3 || n > 12, v = 0; return; end
h = boxes(:,4);  w = boxes(:,3);  x = boxes(:,1);  y = boxes(:,2);
nScore  = min(n, 7) / 7;
hReg    = exp(-8 * (std(h) / mean(h))^2);
fill    = exp(-((mean(h) / 100 - 0.55) / 0.25)^2);
gaps = max(x(2:end) - (x(1:end-1) + w(1:end-1)), 0);
if n >= 4, gaps = sort(gaps);  gaps = gaps(1:end-1); end
spacing = exp(-1.5 * (std(gaps) / (mean(gaps) + 2))^2);
line    = exp(-8 * (std(y + h/2) / mean(h))^2);
v = nScore * hReg * fill * spacing * line;
end
