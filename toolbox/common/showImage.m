function h = showImage(ax, I, ttl)
%SHOWIMAGE  Display a gray/RGB/binary image in an axes without any toolbox.
%   h = SHOWIMAGE(ax, I, title). Pixel values are expected in [0,1] (or uint8).
%   If ax is empty, the current axes are used.

if isempty(ax), ax = gca; end
I = toDouble(I);
I = min(max(I, 0), 1);
if size(I,3) == 1
    I = repmat(I, [1 1 3]);
end
h = image(ax, I);
axis(ax, 'image');
set(ax, 'XTick', [], 'YTick', []);
if nargin >= 3
    args = {'FontWeight', 'normal', 'Interpreter', 'none'};
    if ~isa(ax, 'matlab.ui.control.UIAxes')                % plain figures sit on a white page
        args = [args, {'Color', [0.1 0.1 0.1]}];
    end
    title(ax, ttl, args{:});
end
end
