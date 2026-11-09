function tpl = buildGlyphTemplates(cacheFile)
%BUILDGLYPHTEMPLATES  Render the characters 0-9 and A-Z in many fonts (training material).
%   tpl = BUILDGLYPHTEMPLATES(cacheFile)
%   The result is cached in cacheFile (a .mat file) because rendering needs a
%   figure and takes ~20 s. Delete the cache to rebuild it, e.g. after installing
%   fonts.
%
%   tpl.chars    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
%   tpl.variants cell array {fontName, weight} of the fonts that were rendered
%   tpl.isTest   logical per variant - a few fonts are held out for evaluation
%   tpl.glyphs   glyphs{v}{c} : uint8 ink image (255 = ink) tightly cropped
%   tpl.capH     cap height in pixels of every variant (height of 'H')
%
%   Only base MATLAB is used: every font is drawn once as a 6x6 mosaic into an
%   invisible figure, captured with GETFRAME and cut into single characters.

if nargin > 0 && ~isempty(cacheFile) && exist(cacheFile, 'file')
    S = load(cacheFile);
    tpl = S.tpl;
    return
end

chars = ['0':'9', 'A':'Z'];
wanted = {
    'Arial','normal';  'Arial','bold';  'Tahoma','bold';  'Verdana','normal';  'Verdana','bold'
    'Consolas','normal'; 'Consolas','bold'; 'Courier New','bold'; 'Lucida Console','normal'
    'Segoe UI','normal'; 'Segoe UI','bold'; 'Trebuchet MS','bold'; 'Franklin Gothic Medium','normal'
    'Century Gothic','bold'; 'Calibri','bold'; 'Impact','normal'; 'Arial Black','normal'
    'Times New Roman','bold'; 'Georgia','bold'; 'Cambria','bold'; 'DejaVu Sans','bold'
    'Helvetica','bold'; 'Liberation Sans','bold'};
installed = listfonts;
keepV = ismember(lower(wanted(:,1)), lower(installed));
variants = wanted(keepV, :);
if size(variants, 1) < 3
    variants = {installed{1}, 'normal'; installed{1}, 'bold'; 'monospaced', 'normal'};
    warning('buildGlyphTemplates:fonts', 'Few fonts found - recognition accuracy may be lower.');
end
nV = size(variants, 1);
holdOut = {'Verdana|bold', 'Calibri|bold', 'Trebuchet MS|bold', 'Courier New|bold'};
isTest = false(nV, 1);
for v = 1:nV
    isTest(v) = any(strcmpi(sprintf('%s|%s', variants{v,1}, variants{v,2}), holdOut));
end
if ~any(isTest), isTest(end) = true; end            % always keep at least one font for testing

cell0 = 100;                                           % mosaic cell size in figure pixels
fig = figure('Visible', 'off', 'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none', ...
             'Units', 'pixels', 'Position', [50 50 6*cell0 6*cell0]);
cleanup = onCleanup(@() close(fig));
ax = axes(fig, 'Units', 'normalized', 'Position', [0 0 1 1], 'XLim', [0 6], 'YLim', [0 6], ...
          'YDir', 'reverse', 'Visible', 'off');
glyphs = cell(nV, 1);
capH = zeros(nV, 1);
for v = 1:nV
    delete(findall(ax, 'Type', 'text'));
    for k = 1:36
        col = mod(k-1, 6);  row = floor((k-1) / 6);
        text(ax, col + 0.5, row + 0.5, chars(k), 'FontName', variants{v,1}, 'FontWeight', variants{v,2}, ...
             'FontUnits', 'pixels', 'FontSize', 72, 'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'middle', 'Color', 'k');
    end
    drawnow;
    fr = getframe(fig);
    ink = 1 - toGray(fr.cdata);                        % dark text on white -> ink = 1
    [H, W] = size(ink);
    glyphs{v} = cell(1, 36);
    for k = 1:36
        col = mod(k-1, 6);  row = floor((k-1) / 6);
        r = floor(row * H / 6) + 1 : floor((row + 1) * H / 6);
        c = floor(col * W / 6) + 1 : floor((col + 1) * W / 6);
        g = ink(r, c);
        mask = g > 0.3;
        rr = find(any(mask, 2));  cc = find(any(mask, 1));
        if isempty(rr), rr = 1:size(g,1); cc = 1:size(g,2); end
        g = g(max(rr(1)-1,1):min(rr(end)+1,end), max(cc(1)-1,1):min(cc(end)+1,end));
        glyphs{v}{k} = uint8(255 * min(max(g, 0), 1));
    end
    capH(v) = size(glyphs{v}{find(chars == 'H')}, 1);
end

tpl.chars = chars;
tpl.variants = variants;
tpl.isTest = isTest;
tpl.glyphs = glyphs;
tpl.capH = capH;
if nargin > 0 && ~isempty(cacheFile)
    save(cacheFile, 'tpl');
end
end
