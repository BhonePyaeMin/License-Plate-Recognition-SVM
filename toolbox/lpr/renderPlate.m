function [plate, info] = renderPlate(txt, tpl, v, varargin)
%RENDERPLATE  Draw a license plate image for a given text using font glyph templates.
%   [plate, info] = RENDERPLATE(txt, tpl, v, 'Name', value, ...)
%   txt : plate text (spaces become wider gaps), tpl : glyph templates,
%   v   : font variant index.
%   Options: 'Height' plate height in pixels (default 110)
%            'Style'  'white' | 'yellow' | 'dark' (default random white/yellow)
%   plate : RGB double image;  info.boxes : [x y w h] of every character.

p = inputParser;
p.addParameter('Height', 110);
p.addParameter('Style', '');
p.parse(varargin{:});
H = p.Results.Height;
style = p.Results.Style;
if isempty(style)
    if rand < 0.7, style = 'white'; else, style = 'yellow'; end
end
switch style
    case 'white',  bg = [0.96 0.96 0.93];  fg = [0.07 0.07 0.09];
    case 'yellow', bg = [0.98 0.80 0.12];  fg = [0.05 0.05 0.05];
    case 'dark',   bg = [0.08 0.08 0.10];  fg = [0.95 0.95 0.95];
    otherwise, error('renderPlate:style', 'Unknown plate style "%s".', style);
end

charH = round(H * (0.50 + 0.14 * rand));
s = charH / tpl.capH(v);                                  % scale: cap height -> charH pixels
gap  = round(charH * (0.16 + 0.22 * rand));
wide = round(charH * (0.60 + 0.30 * rand));               % gap for a space in the text
padX = round(charH * (0.55 + 0.45 * rand));

% scale every glyph and measure the text row
n = numel(txt);
gl = cell(1, n);  wd = zeros(1, n);
for k = 1:n
    if txt(k) == ' ', continue; end
    idx = find(tpl.chars == txt(k), 1);
    g = double(tpl.glyphs{v}{idx}) / 255;
    g = imResize(g, max(2, round(size(g) * s)), 'bilinear');
    gl{k} = g;  wd(k) = size(g, 2);
end
total = 0;
for k = 1:n
    if txt(k) == ' ', total = total + wide; else, total = total + wd(k) + gap; end
end
total = total - gap;
W = total + 2 * padX;

% paint characters into an ink-coverage canvas
ink = zeros(H, W);
x = padX;
yc = H / 2 + (rand - 0.5) * 0.04 * H;
boxes = zeros(0, 4);
for k = 1:n
    if txt(k) == ' '
        x = x + wide;  continue;
    end
    g = gl{k};
    [gh, gw] = size(g);
    r0 = round(yc - gh / 2);
    r0 = min(max(r0, 1), H - gh + 1);
    rows = r0 + (0:gh-1);  cols = x + (1:gw);
    ink(rows, cols) = max(ink(rows, cols), g);
    boxes(end+1, :) = [x + 1, r0, gw, gh]; %#ok<AGROW>
    x = x + gw + gap;
end

% border frame
t  = max(2, round(H * 0.035));
in = max(2, round(H * 0.05));
frame = false(H, W);
frame(in+1:in+t, in+1:W-in) = true;       frame(H-in-t+1:H-in, in+1:W-in) = true;
frame(in+1:H-in, in+1:in+t) = true;       frame(in+1:H-in, W-in-t+1:W-in) = true;
ink = max(ink, double(frame));

plate = zeros(H, W, 3);
for ch = 1:3
    plate(:,:,ch) = bg(ch) * (1 - ink) + fg(ch) * ink;
end
info.boxes = boxes;
info.style = style;
end
