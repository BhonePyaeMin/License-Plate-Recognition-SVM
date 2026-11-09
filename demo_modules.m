function demo_modules(imageFile)
%DEMO_MODULES  Run all three toolbox modules on one image and save comparison figures.
%   >> demo_modules                      % uses a synthetic car photo
%   >> demo_modules('images/car1.jpg')
%   Creates results/module1_enhancement.png, module2_edges.png,
%   module2_segmentation.png and module3_geometry.png.

root = fileparts(mfilename('fullpath'));
setup_toolbox;
if ~exist(fullfile(root, 'results'), 'dir'), mkdir(fullfile(root, 'results')); end

if nargin < 1 || isempty(imageFile)
    rng(4);
    tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
    I = makeScene(tpl, find(tpl.isTest), 'Hard', 0.5);
else
    I = toDouble(imread(imageFile));
    if max(size(I, 1), size(I, 2)) > 1000, I = imResize(I, 1000 / max(size(I, 1), size(I, 2))); end
end

vis = get(0, 'DefaultFigureVisible');
set(0, 'DefaultFigureVisible', 'off');
cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', vis));

figs = {compareEnhancement(I),      'module1_enhancement.png'
        compareEdgeDetectors(I),    'module2_edges.png'
        compareSegmentation(I),     'module2_segmentation.png'
        compareGeometry(I),         'module3_geometry.png'};
for k = 1:size(figs, 1)
    saveas(figs{k,1}, fullfile(root, 'results', figs{k,2}));
    close(figs{k,1});
    fprintf('saved results/%s\n', figs{k,2});
end
end
