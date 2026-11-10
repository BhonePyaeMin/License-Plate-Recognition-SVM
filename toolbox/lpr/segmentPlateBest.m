function [chars, boxes, dbg, score] = segmentPlateBest(plate, varargin)
%SEGMENTPLATEBEST  Cut a plate into characters with several settings; the most plate-like row wins.
%   [chars, boxes, dbg, score] = SEGMENTPLATEBEST(plate, 'Name', value, ...)
%   A single Otsu threshold fails when a bright car body, a dark bumper or a yellow background
%   around the plate decides the level, when characters touch each other or the plate frame, or
%   when the plate is tilted. SEGMENTCHARS is therefore run with different settings and the result
%   whose row of characters looks most like a plate (PLATEROWSCORE) is kept. The default setting is
%   kept unless another one is clearly better (margin 0.05), so plates that were readable before
%   are not disturbed.
%   Options: 'Mode'      'full' (default) | 'fast'
%                        full : default, tilt search (+-20 deg), and threshold levels 0.6..1.25 of the Otsu
%                               level computed from the middle of the crop + tilt search (+-32 deg)
%                        fast : default and the threshold-level sweep without tilt search (used to
%                               rate many candidate regions quickly)
%            'Polarity'  'auto' (default) | 'dark' | 'bright'
%            'SegOptions' cell of extra SEGMENTCHARS options
%            'Split'     true (default): when the normal variants find fewer than MinChars (default 4) characters,
%                        also try the variants that cut touching characters apart (see PLATESEGVARIANTS('split'))
%            'Rescue'    'full' (default) | 'light': 'light' leaves out the slow top-hat variants (used while ranking many candidates)
%            'Fix'       true (default): touching characters of the chosen row are cut apart (SEGMENTCHARS option 'FixMerged')
%   score is PLATEROWSCORE of the chosen row, dbg.variant the number of the chosen setting.

p = inputParser;
p.addParameter('Mode', 'full');
p.addParameter('Polarity', 'auto');
p.addParameter('SegOptions', {});
p.addParameter('Split', true);
p.addParameter('MinChars', 4);
p.addParameter('Rescue', 'full');
p.addParameter('Fix', true);
p.parse(varargin{:});
o = p.Results;

V = plateSegVariants(o.Mode);

best = 0;  bestScore = -1;
for v = 1:numel(V)
    [ch, bx, dg] = segmentChars(plate, 'Polarity', o.Polarity, 'FixMerged', o.Fix, V{v}{:}, o.SegOptions{:});
    sc = plateRowScore(bx);
    if v == 1
        chars = ch;  boxes = bx;  dbg = dg;  score = sc;  best = 1;  bestScore = sc;
    elseif ~isempty(ch) && sc > bestScore + 0.05
        chars = ch;  boxes = bx;  dbg = dg;  score = sc;  best = v;  bestScore = sc;
    end
end
if o.Split && numel(chars) < o.MinChars                   % rescue: touching characters (small bold night plates)
    VS = plateSegVariants('split');
    if strcmpi(o.Rescue, 'light'), VS = VS(1:3); end          % light: no top-hat (the top-hat is slow; it is used when reading a chosen plate)
    for v = 1:numel(VS)
        [ch, bx, dg] = segmentChars(plate, 'Polarity', o.Polarity, 'FixMerged', o.Fix, VS{v}{:}, o.SegOptions{:});
        sc = plateRowScore(bx);
        if numel(ch) >= o.MinChars && numel(ch) <= 10 && sc > 0.3 && sc > score
            chars = ch;  boxes = bx;  dbg = dg;  score = sc;  best = numel(V) + v;
        end
    end
end
dbg.variant = best;
end
