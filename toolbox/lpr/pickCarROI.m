function roi = pickCarROI(img, varargin)
%PICKCARROI  Mark ONE car in a photo by clicking two opposite corners (base MATLAB, GINPUT).
%   roi = PICKCARROI(img) shows the photo in a figure window; click two opposite corners of a
%   rectangle around the car you want. Returns roi = [x y w h] in pixels, clipped to the photo,
%   or [] if you cancelled (Enter before the second click, closing the window) or the rectangle is
%   smaller than 'MinSize' pixels.
%   Options: 'MinSize'  smallest accepted width and height in pixels (default 40)
%            'Title'    text above the photo
%   Pass the result to RECOGNIZEPLATE as 'ROI'. GINPUT works only in an ordinary figure (not in a
%   uifigure), which is why the app opens this separate window.

p = inputParser;
p.addParameter('MinSize', 40);
p.addParameter('Title', 'Click two opposite corners around ONE car  (Enter = cancel)');
p.parse(varargin{:});
o = p.Results;

img = toDouble(img);
[H, W, ~] = size(img);
f = figure('Name', 'Pick one car', 'NumberTitle', 'off', 'Color', 'w', ...
           'MenuBar', 'none', 'ToolBar', 'none', 'Units', 'normalized', 'Position', [0.15 0.1 0.7 0.8]);
ax = axes('Parent', f);
showImage(ax, img, o.Title);
roi = [];
try
    [x, y] = ginput(2);
catch                                                      % window closed while waiting
    return
end
if numel(x) < 2, if isvalid(f), close(f); end, return; end
x = min(max(x, 1), W);  y = min(max(y, 1), H);
r = [min(x), min(y), abs(x(2) - x(1)), abs(y(2) - y(1))];
if r(3) >= o.MinSize && r(4) >= o.MinSize
    roi = round(r);
    roi(3) = min(roi(3), W - roi(1) + 1);  roi(4) = min(roi(4), H - roi(2) + 1);
    rectangle(ax, 'Position', roi, 'EdgeColor', 'r', 'LineWidth', 2);
    drawnow;  pause(0.4);
end
if isvalid(f), close(f); end
end
