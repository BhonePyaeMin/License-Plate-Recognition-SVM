function app = LPR_Toolbox(varargin)
%LPR_TOOLBOX  Image-processing toolbox GUI with SVM license plate recognition.
%   >> LPR_Toolbox
%
%   Load an image (or generate a synthetic car photo), pick a technique from one
%   of four tabs and press Apply / Recognise:
%     1 Enhancement   histogram processing, spatial and frequency filters
%     2 Segmentation  edges, thresholding, region growing, colour, morphology
%     3 Geometry      translate / scale / rotate / affine, interpolation,
%                     radial distortion, image registration
%     4 Plate (SVM)   detect the plate, cut the characters, read them with an SVM. "Find ALL plates" reads every plate of a road
%                     scene, "Night vision" searches a brightened copy of a dark photo; "Crop" works like the crop tool of a photo editor:
%                     press it, drag a rectangle around one car or plate on the photo, and every plate in it is read at once and added to the list;
%                     the number of every plate is written above its box, above its picture and above the characters the SVM saw.
%   The original (left) and the result (right) are shown side by side, with the histograms of
%   both under them for Module 1. The last entry of every module is a "Compare: ..." view that shows
%   several methods in one picture. "Use result as input" chains operations (e.g. equalise, then Canny).
%   The panel on the right ("Filters") filters the ORIGINAL photo with up to four filters
%   (resolution, convolution with your own matrix, mean / Gaussian / median / bilateral, sharpening,
%   deblurring, brightness and contrast, local histogram equalisation, illumination, frequency domain).
%   The filtered photo appears next to the original as soon as a filter, a number or the matrix changes.
%   "Recognise on filtered photo" searches the plate in the filtered picture, "Compare" reads
%   the original and the filtered photo and shows both results.
%
%   app = LPR_Toolbox('Visible','off') returns handles for scripted testing.

p = inputParser;
p.addParameter('Visible', 'on');
p.parse(varargin{:});

root = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(root, 'toolbox')));
ops = toolboxOperations();

% ------------------------------- state -------------------------------------
S.orig = [];  S.I = [];  S.ref = [];  S.result = [];
S.model = [];  S.tpl = [];  S.truth = '';  S.lastRes = [];  S.realIdx = 0;
S.filtered = [];  S.filterNote = {};  S.useFilters = true;  S.mute = false;  S.guide = {};
fpad = 'replicate';                                                % border handling of the spatial filters (pixels outside the picture)
S.plates = [];  S.unread = [];  S.crops = zeros(0, 4);  S.cropMode = false;  S.boxH = gobjects(0);  S.gal = [];
drag = struct('on', false, 'p0', [0 0], 'p1', [0 0], 'h', gobjects(0));       % the rectangle being dragged on the photo (crop tool)
fops = prefilterOps();

% ------------------------------- layout ------------------------------------
scr = get(0, 'ScreenSize');                                       % the window must fit the screen (Windows display scaling makes it smaller than it looks)
figW = min(1560, scr(3) - 20);  figH = min(860, scr(4) - 90);
fig = uifigure('Name', 'License Plate Recognition Using SVM - Image Processing Toolbox', ...
               'Position', [max(1, round((scr(3) - figW) / 2)), max(1, round((scr(4) - figH) / 2)), figW, figH], 'Visible', p.Results.Visible);
if strcmp(p.Results.Visible, 'on')
    try fig.WindowState = 'maximized'; catch, end                  %#ok<CTCH>
end
main = uigridlayout(fig, [1 3]);
main.ColumnWidth = {340, '1x', 360};  main.Padding = [8 8 8 8];

left = uigridlayout(main, [3 1]);
left.RowHeight = {170, '1x', 110};  left.Padding = [0 0 0 0];

fileGrid = uigridlayout(left, [5 2]);
fileGrid.Padding = [0 0 0 0];  fileGrid.RowSpacing = 5;
uibutton(fileGrid, 'push', 'Text', 'Open image...',     'ButtonPushedFcn', @(~,~) onOpen());
uibutton(fileGrid, 'push', 'Text', 'Open reference...', 'ButtonPushedFcn', @(~,~) onOpenRef());
uibutton(fileGrid, 'push', 'Text', 'Synthetic car photo', 'ButtonPushedFcn', @(~,~) onSample());
uibutton(fileGrid, 'push', 'Text', 'Real car photo',      'ButtonPushedFcn', @(~,~) onRealSample());
uibutton(fileGrid, 'push', 'Text', 'Save result...',    'ButtonPushedFcn', @(~,~) onSave());
uibutton(fileGrid, 'push', 'Text', 'Use result as input', 'ButtonPushedFcn', @(~,~) onChain());
uibutton(fileGrid, 'push', 'Text', 'Reset to original', 'ButtonPushedFcn', @(~,~) onReset());
fileLabel = uilabel(fileGrid, 'Text', 'No image loaded.', 'WordWrap', 'on');
fileLabel.Layout.Row = 5;  fileLabel.Layout.Column = [1 2];

tabs = uitabgroup(left);
names = {'1 Enhance', '2 Segment', '3 Geom.', '4 Plate'};
ui = repmat(struct('idx', [], 'dd', [], 'lbl', [], 'sld', [], 'help', []), 1, 3);
for m = 1:3
    t = uitab(tabs, 'Title', names{m});
    ui(m) = buildOpTab(t, m);
end
tabPlate = uitab(tabs, 'Title', names{4});
plate = buildPlateTab(tabPlate);

infoBox = uitextarea(left, 'Editable', 'off', 'Value', {'Open an image or press "Synthetic car photo".'});

right = uigridlayout(main, [2 2]);
right.RowHeight = {'1.6x', '1x'};  right.ColumnWidth = {'1x', '1x'};  right.Padding = [0 0 0 0];         % original and filtered / result photo side by side, equally wide
axOrig = uiaxes(right);  axRes = uiaxes(right);
axAux  = uiaxes(right);  axAux.Layout.Row = 2;  axAux.Layout.Column = [1 2];
cla(axOrig); clearResult(); resetAux();
axis(axAux, 'off');
axInter = axOrig.Interactions;                                     % restored when the crop tool is switched off
fp = uipanel(main, 'Title', 'Filters (the filtered photo appears next to the original)');
filt = buildFilterPanel(fp);
fig.WindowButtonDownFcn   = @(~, ~) onMouseDown();                % crop tool: drag a rectangle on the photo
fig.WindowButtonMotionFcn = @(~, ~) onMouseMove();
fig.WindowButtonUpFcn     = @(~, ~) onMouseUp();

% ------------------------------- public handles ------------------------------
app.fig = fig;
app.loadImage  = @loadImage;
app.applyByName = @applyByName;
app.recognize  = @onRecognize;
app.realSample = @onRealSample;
app.recognizeAll = @recognizeAllScripted;
app.state      = @getState;
app.setFilters = @setFiltersScripted;                             % app.setFilters(chain, kernelText): fills Filter 1-4; the filtered photo is shown at once
app.showFiltered = @livePreview;
app.recognizeFiltered = @onRecognizeFiltered;
app.compareFilters = @onCompareFilters;
app.clearFilters = @onClearFilters;
app.showPlate  = @showPlateDetail;
app.cropRead   = @readCropBox;                                    % scripted crop tool: app.cropRead([x y w h]) = drag that rectangle on the photo
app.cropDrag   = @dragCropScripted;
app.removePlate = @onRemovePlate;
app.openFile = @openFileScripted;
app.operations = ops;

% ============================== construction ================================
    function h = buildFilterPanel(parent)
        g = uigridlayout(parent, [10 1]);
        g.RowHeight = {20, 54, 54, 54, 54, 20, 52, 34, 30, '1x'};
        g.Padding = [8 6 8 6];  g.RowSpacing = 4;  g.Scrollable = 'on';
        sectionLabel(g, 'Filters (run in this order on the ORIGINAL photo)');
        h.on = gobjects(1, 4);  h.dd = gobjects(1, 4);
        h.l1 = gobjects(1, 4);  h.p1 = gobjects(1, 4);  h.l2 = gobjects(1, 4);  h.p2 = gobjects(1, 4);
        for k = 1:4
            sg = uigridlayout(g, [2 4]);
            sg.RowHeight = {26, 26};  sg.ColumnWidth = {'1x', 56, '1x', 56};  sg.Padding = [0 0 0 0];  sg.RowSpacing = 2;  sg.ColumnSpacing = 4;
            top = uigridlayout(sg, [1 2]);  top.Layout.Row = 1;  top.Layout.Column = [1 4];
            top.ColumnWidth = {78, '1x'};  top.Padding = [0 0 0 0];
            h.on(k) = uicheckbox(top, 'Text', sprintf('Filter %d', k), 'Value', false, 'ValueChangedFcn', @(~, ~) livePreview(), ...
                                 'Tooltip', 'Tick = use this filter. Choose the filter in the list on the right.');
            h.dd(k) = uidropdown(top, 'Items', [{'(none)'}, {fops.name}], 'ItemsData', num2cell(0:numel(fops)), 'Value', 0, ...
                                 'ValueChangedFcn', @(~, ~) onFilterChanged(k, true));
            h.l1(k) = uilabel(sg, 'Text', '', 'Visible', 'off', 'HorizontalAlignment', 'right');
            h.p1(k) = uieditfield(sg, 'numeric', 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) livePreview());
            h.l2(k) = uilabel(sg, 'Text', '', 'Visible', 'off', 'HorizontalAlignment', 'right');
            h.p2(k) = uieditfield(sg, 'numeric', 'Value', 0, 'Visible', 'off', 'ValueChangedFcn', @(~, ~) livePreview());
        end
        sectionLabel(g, 'Own matrix (for "Convolution with my own kernel")');
        kg = uigridlayout(g, [2 2]);
        kg.RowHeight = {24, 24};  kg.ColumnWidth = {70, '1x'};  kg.Padding = [0 0 0 0];  kg.RowSpacing = 2;
        uilabel(kg, 'Text', 'Preset:');
        h.preset = uidropdown(kg, 'Items', kernelPresets(1), 'ItemsData', num2cell(1:numel(kernelPresets(1))), 'Value', 1, ...
                              'ValueChangedFcn', @(~, ~) onKernelPreset());
        uilabel(kg, 'Text', 'Matrix:');
        h.kernel = uieditfield(kg, 'text', 'Value', kernelPresets(2, 1), 'ValueChangedFcn', @(~, ~) livePreview(), ...
                               'Tooltip', 'odd size, e.g. [0 -1 0; -1 5 -1; 0 -1 0]; edit the numbers and press Enter');
        uibutton(g, 'push', 'Text', 'Recognise on filtered photo', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onRecognizeFiltered());
        pg2 = uigridlayout(g, [1 2]);  pg2.Padding = [0 0 0 0];  pg2.ColumnSpacing = 5;
        uibutton(pg2, 'push', 'Text', 'Compare with original', 'ButtonPushedFcn', @(~, ~) onCompareFilters(), ...
                 'Tooltip', 'Read the original and the filtered photo and print both results');
        uibutton(pg2, 'push', 'Text', 'Remove filters', 'ButtonPushedFcn', @(~, ~) onClearFilters(), ...
                 'Tooltip', 'Go back to the original photo');
        h.report = uitextarea(g, 'Editable', 'off', 'FontSize', 13, 'Value', {'No filter chosen: the original photo is used. Pick a filter in the list above; the filtered photo appears next to the original.'});
    end

    function h = buildOpTab(tab, m)
        g = uigridlayout(tab, [9 1]);
        g.RowHeight = {28, 20, 22, 20, 22, 20, 22, 32, '1x'};  g.Padding = [6 6 6 6];  g.RowSpacing = 4;
        idx = find([ops.module] == m);
        h.idx = idx;
        h.dd = uidropdown(g, 'Items', {ops(idx).name}, 'ItemsData', num2cell(idx), ...
                          'ValueChangedFcn', @(~,~) onOpChanged(m));
        h.lbl = gobjects(1, 3);  h.sld = gobjects(1, 3);
        for k = 1:3
            h.lbl(k) = uilabel(g, 'Text', '');
            h.sld(k) = uislider(g, 'Limits', [0 1], 'Value', 0, 'MajorTicks', [], 'MinorTicks', [], ...
                                'ValueChangingFcn', @(s, e) onSliding(m, k, e.Value), ...
                                'ValueChangedFcn',  @(s, e) onSliding(m, k, e.Value));
        end
        uibutton(g, 'push', 'Text', 'Apply', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) onApply(m));
        h.help = uilabel(g, 'Text', '', 'WordWrap', 'on', 'FontSize', 12, 'VerticalAlignment', 'top');      % what the chosen operation does and when to use it
        % rows: dd, (lbl, sld) x 3, button, help  -> reorder not needed, grid fills in creation order
        ui(m) = h; %#ok<NASGU>
        refreshParams(h, m);
    end

    function h = buildPlateTab(tab)
        accent = [0.10 0.45 0.85];
        g = uigridlayout(tab, [15 1]);
        g.RowHeight = {20, 36, 22, 22, 22, 20, 32, 40, 20, 30, 50, 20, 52, 30, '1x'};  g.Padding = [6 6 6 6];  g.RowSpacing = 4;  g.Scrollable = 'on';
        sectionLabel(g, '1   Whole photo');
        uibutton(g, 'push', 'Text', 'Recognise plate', 'FontWeight', 'bold', 'FontSize', 14, 'BackgroundColor', accent, 'FontColor', [1 1 1], ...
                 'Tooltip', 'Search the whole photo (or the filtered photo when Filter 1 to Filter 4 are ticked)', 'ButtonPushedFcn', @(~,~) onRecognize());
        h.all = uicheckbox(g, 'Text', 'Find ALL plates (road scene with many cars)', 'Value', true, ...
                           'Tooltip', 'Untick to read only the best plate of the photo');
        h.night = uicheckbox(g, 'Text', 'Night vision (dark photo)', 'Value', false, ...
                             'Tooltip', 'Removes the illumination, lifts the shadows and reduces noise, then searches this copy too');
        h.vote = uicheckbox(g, 'Text', 'Vote over filtered copies (slower, +3 % exact)', 'Value', false);
        sectionLabel(g, '2   Crop one car (like a photo crop)');
        cg = uigridlayout(g, [1 2]);  cg.Padding = [0 0 0 0];  cg.ColumnSpacing = 5;  cg.ColumnWidth = {'1x', 100};
        h.crop = uibutton(cg, 'state', 'Text', 'Crop', 'FontWeight', 'bold', 'Value', false, ...
                          'Tooltip', 'Press, then drag a rectangle around ONE car or plate on the photo', 'ValueChangedFcn', @(s, ~) onCropToggle(s.Value));
        icn = fullfile(root, 'toolbox', 'icons', 'crop.png');
        if exist(icn, 'file'), try h.crop.Icon = icn; catch, end, end         %#ok<CTCH>
        uibutton(cg, 'push', 'Text', 'Clear crops', 'ButtonPushedFcn', @(~, ~) onClearCrops(), 'Tooltip', 'Remove the crop frames from the photo');
        h.hint = uilabel(g, 'Text', 'Press Crop, then drag a box around ONE car or plate on the photo. It is read at once and added to the list. Drag again for the next car.', ...
                         'WordWrap', 'on', 'FontSize', 11, 'VerticalAlignment', 'top');
        sectionLabel(g, '3   Plates found');
        sp = uigridlayout(g, [1 3]);  sp.Padding = [0 0 0 0];  sp.ColumnSpacing = 5;  sp.ColumnWidth = {'1x', 64, 56};
        h.pick = uidropdown(sp, 'Items', {'-'}, 'ItemsData', {0}, 'Value', 0, 'ValueChangedFcn', @(~, ~) onPickPlate(), ...
                            'Tooltip', 'The plate whose segmentation is shown in "Result" (click a picture of the gallery to choose it too)');
        uibutton(sp, 'push', 'Text', 'Remove', 'ButtonPushedFcn', @(~, ~) onRemovePlate(), 'Tooltip', 'Delete the chosen reading from the list (a wrong box, a sign, a lamp)');
        uibutton(sp, 'push', 'Text', 'Copy', 'ButtonPushedFcn', @(~, ~) onCopyPlates(), 'Tooltip', 'Copy all plate numbers to the clipboard');
        h.result = uilabel(g, 'Text', '', 'FontSize', 24, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'WordWrap', 'on');
        sectionLabel(g, 'Options');
        og = uigridlayout(g, [2 2]);  og.Padding = [0 0 0 0];  og.RowHeight = {24, 24};  og.ColumnWidth = {110, '1x'};  og.RowSpacing = 4;
        uilabel(og, 'Text', 'Plate layout:');
        h.format = uieditfield(og, 'text', 'Value', '', 'Placeholder', 'L = letter, D = digit: LLL DDDD', ...
                               'Tooltip', 'Optional: L = letter, D = digit, e.g. LLL DDDD');
        uilabel(og, 'Text', 'Character colour:');
        h.polarity = uidropdown(og, 'Items', {'auto', 'dark', 'bright'}, 'Value', 'auto');
        pg = uigridlayout(g, [1 2]);  pg.Padding = [0 0 0 0];  pg.ColumnSpacing = 5;
        uibutton(pg, 'push', 'Text', 'Show pipeline stages', 'ButtonPushedFcn', @(~,~) onPipeline());
        uibutton(pg, 'push', 'Text', 'Train SVM model...', 'ButtonPushedFcn', @(~,~) onTrain());
    end

    function sectionLabel(g, txt)
        uilabel(g, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 13, 'FontColor', [0.25 0.6 1]);
    end

    function refreshParams(h, m)
        g = ops(h.dd.Value);
        h.help.Text = g.help;
        for k = 1:3
            if k <= numel(g.params)
                q = g.params(k);
                h.sld(k).Limits = [q.min q.max];
                h.sld(k).Value = min(max(q.default, q.min), q.max);
                h.lbl(k).Text = sprintf('%s: %.3g', q.label, h.sld(k).Value);
                h.lbl(k).Visible = 'on';  h.sld(k).Visible = 'on';
            else
                h.lbl(k).Visible = 'off';  h.sld(k).Visible = 'off';
            end
        end
        ui(m) = h;
    end

% ================================ callbacks =================================
    function onOpChanged(m)
        refreshParams(ui(m), m);
    end

    function onSliding(m, k, val)
        g = ops(ui(m).dd.Value);
        ui(m).lbl(k).Text = sprintf('%s: %.3g', g.params(k).label, val);
    end

    function onOpen()
        [f, d] = uigetfile({'*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.tif;*.tiff', 'Images (jpg, jfif, png, bmp, tif)'; '*.*', 'All files'}, 'Select an image');
        if isequal(f, 0), return; end
        try
            S.truth = '';                                         % a photo of your own has no known true plate (the old text stayed on screen)
            loadImage(readImageFile(fullfile(d, f)), f);
        catch ME
            uialert(fig, imageErrorText(ME, f), 'Cannot read image');
        end
    end

    function img = readImageFile(f)
        % imread, with a second try as JPEG for files saved with an unusual name (.jfif, no extension)
        try
            img = imread(f);
        catch ME
            [~, ~, ext] = fileparts(f);
            if any(strcmpi(ext, {'.jfif', '.jpe', '.jfi', ''}))
                img = imread(f, 'jpg');
            else
                rethrow(ME);
            end
        end
    end

    function openFileScripted(f)
        % scripted access: app.openFile('photo.jfif') = "Open image..." without the file dialog
        [~, nm, ext] = fileparts(f);
        S.truth = '';
        loadImage(readImageFile(f), [nm ext]);
    end

    function onOpenRef()
        [f, d] = uigetfile({'*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.tif;*.tiff', 'Images (jpg, jfif, png, bmp, tif)'; '*.*', 'All files'}, 'Select a reference image');
        if isequal(f, 0), return; end
        try
            S.ref = limitSize(toDouble(readImageFile(fullfile(d, f))));
            log_(sprintf('Reference image loaded: %s', f));
        catch ME
            uialert(fig, imageErrorText(ME, f), 'Cannot read image');
        end
    end

    function onSample()
        if isempty(S.tpl)
            fig.Pointer = 'watch';  drawnow;
            S.tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
            fig.Pointer = 'arrow';
        end
        [img, gt] = makeScene(S.tpl, find(S.tpl.isTest), 'Hard', 0.4);
        S.truth = gt.text;
        loadImage(img, sprintf('synthetic car photo (true plate: %s)', gt.text));
    end

    function onRealSample()
        % cycle through the real photos in images/real (Wikimedia Commons), showing the true plate
        f = fullfile(root, 'images', 'real', 'labels.csv');
        if ~exist(f, 'file')
            uialert(fig, 'images/real/labels.csv was not found.', 'Real photos'); return;
        end
        T = readtable(f, 'TextType', 'string', 'Delimiter', ',');
        T = T(isfile(fullfile(root, 'images', 'real', T.file)), :);        % the OpenALPR photos are not in the repository
        S.realIdx = mod(S.realIdx, height(T)) + 1;
        k = S.realIdx;
        S.truth = char(T.plate_text(k));
        loadImage(imread(fullfile(root, 'images', 'real', T.file(k))), ...
                  sprintf('real photo %s (true plate: %s, %s)', T.file(k), T.plate_text(k), T.split(k)));
    end

    function loadImage(img, label)
        if nargin < 2, label = 'image'; end
        img = limitSize(toDouble(img));
        if size(img, 3) == 4, img = img(:,:,1:3); end
        S.orig = img;  S.I = img;  S.result = [];  S.lastRes = [];  S.filtered = [];  S.filterNote = {};  S.plates = [];  S.unread = [];  S.crops = zeros(0, 4);  S.boxH = gobjects(0);  S.gal = [];
        try plate.pick.Items = {'-'};  plate.pick.ItemsData = {0};  plate.pick.Value = 0;  plate.result.Text = ''; catch, end   %#ok<CTCH>
        try setStagesFromChain([]);  filt.report.Value = {'A new photo is loaded: Filter 1 to Filter 4 were cleared.'}; catch, end   %#ok<CTCH>
        fileLabel.Text = sprintf('%s  (%d x %d)', label, size(img, 2), size(img, 1));
        showImage(axOrig, S.I, 'Original');
        clearResult();  resetAux();  axis(axAux, 'off');
        title(axRes, 'Result');
        log_(['Loaded ' label]);
    end

    function img = limitSize(img)
        % keep the GUI responsive: scale very large photos down to 1920 px (plates need many pixels)
        m = max(size(img, 1), size(img, 2));
        if m > 1920, img = imResize(img, 1920 / m, 'bilinear'); end
    end

    function onReset()
        if isempty(S.orig), return; end
        S.I = S.orig;  S.result = [];
        showImage(axOrig, S.I, 'Original');  clearResult();  resetAux();
        log_('Input reset to the original image.');
    end

    function onChain()
        if isempty(S.result), return; end
        S.I = S.result;
        if size(S.I, 3) == 1, S.I = repmat(S.I, [1 1 3]); end
        showImage(axOrig, S.I, 'Input (previous result)');
        log_('Result is now the input image.');
    end

    function onSave()
        if isempty(S.result), uialert(fig, 'Nothing to save yet.', 'Save'); return; end
        [f, d] = uiputfile({'*.png', 'PNG image'; '*.jpg', 'JPEG image'}, 'Save result', 'result.png');
        if isequal(f, 0), return; end
        imwrite(min(max(S.result, 0), 1), fullfile(d, f));
        log_(['Saved ' fullfile(d, f)]);
    end

    function onApply(m)
        g = ops(ui(m).dd.Value);
        pv = zeros(1, numel(g.params));
        for k = 1:numel(g.params), pv(k) = ui(m).sld(k).Value; end
        runOp(g, pv);
    end

    function applyByName(name, pv)
        % scripted access: applyByName('Canny edges', [0 1.4])
        k = find(strcmp({ops.name}, name), 1);
        if isempty(k), error('LPR_Toolbox:op', 'No operation called "%s".', name); end
        if nargin < 2
            pv = arrayfun(@(q) q.default, ops(k).params);
        end
        % drive the controls exactly like a user would: tab, drop-down, sliders
        m = ops(k).module;
        tabs.SelectedTab = tabs.Children(m);
        ui(m).dd.Value = k;
        refreshParams(ui(m), m);
        for q = 1:numel(pv)
            lim = ui(m).sld(q).Limits;
            ui(m).sld(q).Value = min(max(pv(q), lim(1)), lim(2));
            onSliding(m, q, ui(m).sld(q).Value);
        end
        runOp(ops(k), pv);
    end

    function runOp(g, pv)
        if isempty(S.I), uialert(fig, 'Open an image first.', 'No image'); return; end
        fig.Pointer = 'watch';  drawnow;
        t0 = tic;
        try
            [J, info] = g.run(S.I, pv, S.ref);
        catch ME
            fig.Pointer = 'arrow';
            uialert(fig, ME.message, 'Operation failed');
            return
        end
        fig.Pointer = 'arrow';
        S.result = min(max(J, 0), 1);
        showImage(axOrig, S.I, 'Input');
        showImage(axRes, S.result, g.name);
        if ~isempty(g.tiles), drawTileLabels(g.tiles, g.grid, S.result); end
        if g.module == 1 && isempty(g.tiles), drawHistograms(S.I, S.result); else, resetAux(); axis(axAux, 'off'); end
        log_(sprintf('%s  [%.2f s]\n%s', g.name, toc(t0), info));
    end

    function drawTileLabels(labels, grid, canvas)
        % the name of every tile of a "Compare: ..." picture (tile layout of toolboxOperations: 4 px gap)
        gap = 4;  R = grid(1);  C = grid(2);
        tw = (size(canvas, 2) - (C - 1) * gap) / C;  th = (size(canvas, 1) - (R - 1) * gap) / R;
        hold(axRes, 'on');
        for k = 1:numel(labels)
            r = ceil(k / C);  c = mod(k - 1, C) + 1;
            text(axRes, (c - 1) * (tw + gap) + 4, (r - 1) * (th + gap) + 4, labels{k}, 'Color', [1 1 0], 'BackgroundColor', [0 0 0], 'Margin', 1, ...
                 'FontSize', 9, 'FontWeight', 'bold', 'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'Interpreter', 'none', 'Clipping', 'on');
        end
        hold(axRes, 'off');
    end

    function drawHistograms(A, B)
        ga = toGray(A);  gb = toGray(B);
        ha = accumarray(min(floor(ga(:) * 64), 63) + 1, 1, [64 1]);
        hb = accumarray(min(floor(gb(:) * 64), 63) + 1, 1, [64 1]);
        resetAux();  axis(axAux, 'on');
        x = ((1:64) - 0.5) / 64;
        hold(axAux, 'on');
        plot(axAux, x, ha / sum(ha), 'Color', [0.2 0.3 0.9], 'LineWidth', 1.6);
        plot(axAux, x, hb / sum(hb), 'Color', [0.9 0.4 0.1], 'LineWidth', 1.6);
        hold(axAux, 'off');
        legend(axAux, {'input', 'result'}, 'Location', 'northeast');
        title(axAux, 'Gray-level histograms');  xlabel(axAux, 'intensity');  ylabel(axAux, 'fraction of pixels');
        xlim(axAux, [0 1]);
    end

% ------------------------------- pre-filter panel -------------------------------
    function onKernelPreset()
        filt.kernel.Value = kernelPresets(2, filt.preset.Value);
        livePreview();
    end

    function onFilterChanged(k, userChoice)
        if nargin < 2, userChoice = false; end
        idx = filt.dd(k).Value;
        labs = {filt.l1(k), filt.l2(k)};  eds = {filt.p1(k), filt.p2(k)};
        if idx == 0
            filt.on(k).Value = false;
            for q = 1:2, labs{q}.Visible = 'off';  eds{q}.Visible = 'off'; end
            filt.dd(k).Tooltip = '';
            if userChoice, S.guide = {};  livePreview(); end
            return
        end
        op = fops(idx);
        filt.dd(k).Tooltip = [op.group ': ' op.name];
        for q = 1:2
            if q <= numel(op.params)
                lim = [op.params(q).min, op.params(q).max];
                eds{q}.Limits = [-Inf Inf];  eds{q}.Value = op.params(q).default;  eds{q}.Limits = lim;
                labs{q}.Text = op.params(q).label;
                labs{q}.Tooltip = sprintf('%s (allowed %g to %g)', op.params(q).tip, lim(1), lim(2));
                eds{q}.Tooltip = labs{q}.Tooltip;
                labs{q}.Visible = 'on';  eds{q}.Visible = 'on';
            else
                labs{q}.Visible = 'off';  eds{q}.Visible = 'off';
            end
        end
        filt.on(k).Value = true;
        if userChoice                                             % explain the chosen filter, then show the filtered photo
            S.guide = [{''; op.name}; helpLines(op)];
            livePreview();
        end
    end

    function lines = helpLines(op)
        % what a filter does and the allowed range of its numbers
        lines = {op.help};
        for q = 1:numel(op.params)
            lines{end+1} = sprintf('  %s: %s (allowed %g to %g, start value %g)', op.params(q).label, op.params(q).tip, ...
                                   op.params(q).min, op.params(q).max, op.params(q).default); %#ok<AGROW>
        end
        lines = lines(:);
    end

    function unmute()
        S.mute = false;
    end

    function setStagesFromChain(chain)
        S.mute = true;  cl = onCleanup(@() unmute());              %#ok<NASGU>  no preview while the boxes are filled in by the program
        for k = 1:4
            filt.dd(k).Value = 0;  onFilterChanged(k);
        end
        if ~isstruct(chain) || isempty(chain), return; end
        for k = 1:min(4, numel(chain))
            idx = find(strcmp({fops.name}, chain(k).name), 1);
            if isempty(idx), continue; end
            filt.dd(k).Value = idx;  onFilterChanged(k);
            eds = {filt.p1(k), filt.p2(k)};
            for q = 1:min(numel(fops(idx).params), numel(chain(k).p))
                lim = eds{q}.Limits;
                eds{q}.Value = min(max(chain(k).p(q), lim(1)), lim(2));
            end
        end
    end

    function chain = chainFromPanel()
        chain = struct('name', {}, 'p', {});
        for k = 1:4
            idx = filt.dd(k).Value;
            if idx == 0 || ~filt.on(k).Value, continue; end
            p = [filt.p1(k).Value, filt.p2(k).Value];
            chain(end+1) = struct('name', fops(idx).name, 'p', p(1:numel(fops(idx).params))); %#ok<AGROW>
        end
    end

    function [K, ok] = parseKernel(needed)
        % the matrix typed by the user; only digits, spaces, . - + e ; , [ ] / are accepted
        K = [0 -1 0; -1 5 -1; 0 -1 0];  ok = true;
        if ~needed, return; end
        txt = strtrim(filt.kernel.Value);
        K0 = [];
        if ~isempty(regexp(txt, '^[\[\]\d\s\.\-\+eE;,/]+$', 'once'))
            try K0 = str2num(txt); catch, K0 = []; end %#ok<ST2NM,CTCH>
        end
        if isempty(K0) || ~isnumeric(K0) || ~all(isfinite(K0(:))) || any(mod(size(K0), 2) == 0)
            ok = false;
            uialert(fig, 'The kernel must be a numeric matrix with an odd number of rows and columns, e.g. [0 -1 0; -1 5 -1; 0 -1 0].', 'Kernel');
            return
        end
        K = K0;
    end

    function [F, ok] = runFilters()
        F = [];  ok = false;
        if isempty(S.orig), uialert(fig, 'Open an image first.', 'No image'); return; end
        chain = chainFromPanel();
        [K, kok] = parseKernel(any(strcmp({chain.name}, 'Convolution with my own kernel')));
        if ~kok, return; end
        fig.Pointer = 'watch';  drawnow;
        try
            [F, rep] = applyPrefilters(S.orig, chain, 'Pad', fpad, 'Kernel', K);
        catch ME
            fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Filter failed');  return;
        end
        fig.Pointer = 'arrow';
        gF = toGray(F);
        if ~isempty(rep) && (mean(gF(:)) < 0.03 || mean(gF(:)) > 0.97 || std(gF(:)) < 0.02)   % an edge kernel, a huge gain, ... destroyed the picture
            rep{end+1} = ['WARNING: the filtered photo is almost completely black, white or flat: these filters destroyed the picture ' ...
                          '(an edge kernel such as Laplacian or Sobel does this). Change the filters or press "Remove filters".'];
        end
        S.filterNote = rep;
        if isempty(rep)
            filt.report.Value = [{'No filter selected: the original photo is used.'}; S.guide(:)];
        else
            filt.report.Value = [{sprintf('%d filter(s) on the original photo:', numel(rep))}; rep(:); S.guide(:)];
        end
        ok = true;
    end

    function livePreview()
        % the filtered photo is shown next to the original every time a filter, a number or the matrix changes
        if S.mute || isempty(S.orig), return; end
        [F, ok] = runFilters();
        if ~ok, return; end
        S.filtered = F;
        if isempty(S.filterNote)
            clearResult();                                        % no filter active: nothing to compare
        else
            showImage(axRes, F, sprintf('Filtered photo (%d filter(s), %d x %d px)', numel(S.filterNote), size(F, 2), size(F, 1)));
        end
    end

    function setUseFilters()
        S.useFilters = true;
    end

    function onRecognizeFiltered()
        [F, ok] = runFilters();
        if ~ok || ~ensureModel(), return; end
        S.filtered = F;  S.I = F;
        onRecognize();
        extra = {};
        if ~plate.all.Value && ~isempty(S.lastRes) && ~S.lastRes.found && ~isempty(S.filterNote)
            % nothing found in the filtered photo: say whether the filters are to blame
            opts = {'Format', plate.format.Value, 'Polarity', plate.polarity.Value, 'Consensus', plate.vote.Value};
            try r0 = recognizePlate(S.orig, S.model, opts{:}); catch, r0 = []; end %#ok<CTCH>
            if ~isempty(r0) && r0.found
                extra = {'', sprintf('The ORIGINAL photo reads %s, so these filters made it worse. Press "Remove filters" or try other filters.', r0.text)};
            else
                extra = {'', 'The original photo gives no plate either, so the filters are not the cause: see the hint above.'};
            end
        end
        if ~isempty(S.filterNote)
            infoBox.Value = [infoBox.Value(:); extra(:); {''; 'Filters used on the original photo:'}; S.filterNote(:)];
            if ~isempty(extra), filt.report.Value = [extra(2); {''; 'Filters used on the original photo:'}; S.filterNote(:)]; end
        end
    end

    function onCompareFilters()
        if isempty(S.orig), uialert(fig, 'Open an image first.', 'No image'); return; end
        if plate.all.Value
            uialert(fig, 'Compare reads one plate at a time: untick "Find ALL plates" first.', 'Compare'); return;
        end
        [F, ok] = runFilters();
        if ~ok || ~ensureModel(), return; end
        fig.Pointer = 'watch';  drawnow;
        opts = {'Format', plate.format.Value, 'Polarity', plate.polarity.Value, 'Consensus', plate.vote.Value};
        try
            r0 = recognizePlate(S.orig, S.model, opts{:});
        catch ME
            fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        fig.Pointer = 'arrow';
        S.filtered = F;  S.I = F;
        S.useFilters = false;
        onRecognize();
        S.useFilters = true;
        r1 = S.lastRes;
        lines = {'', 'Comparison:', ['  original photo: ' describeResult(r0)], ['  filtered photo: ' describeResult(r1)]};
        if ~isempty(S.truth)
            lines{end+1} = ['  true plate: ' S.truth ' - original ' yesNo(r0, S.truth) ', filtered ' yesNo(r1, S.truth)];
        end
        infoBox.Value = [infoBox.Value(:); lines(:); {'Filters:'}; S.filterNote(:)];
        filt.report.Value = [lines(2:end).'; {'Filters:'}; S.filterNote(:)];        % the panel's own box is larger
    end

    function s = describeResult(r)
        if isempty(r), s = '(no result)';  return; end
        if r.found, s = sprintf('%s (vote confidence %.0f %%)', r.text, 100 * mean(r.conf));
        else, s = sprintf('no plate (%s)', r.reason); end
    end

    function s = yesNo(r, truth)
        if ~isempty(r) && r.found && strcmp(r.text, truth), s = 'RIGHT'; else, s = 'wrong'; end
    end

    function onClearFilters()
        if isempty(S.orig), return; end
        S.I = S.orig;  S.filtered = [];  S.filterNote = {};  S.guide = {};
        setStagesFromChain([]);                                   % the boxes are cleared too, otherwise "Recognise plate" would apply them again
        showImage(axOrig, S.I, 'Original');  clearResult();  resetAux();
        filt.report.Value = {'No filter active: the original photo is used.'};
        log_('Filters removed: the original photo is the input again.');
    end

    function setFiltersScripted(chain, kernelText)
        % scripted access: app.setFilters(struct('name', 'Median filter', 'p', 3)) fills Filter 1 to Filter 4; the filtered photo is shown at once
        setStagesFromChain(chain);
        if nargin > 1 && ~isempty(kernelText), filt.kernel.Value = kernelText; end
        livePreview();
    end

% ---------------------------- plate recognition ------------------------------
    function ok = ensureModel()
        ok = true;
        f = fullfile(root, 'models', 'lpr_svm_model_real.mat');      % trained with the real photos
        if ~isempty(S.model) && (~isfield(S.model, 'plate') || isempty(S.model.plate)) && exist(f, 'file')
            S.model = [];                                             % a font-only model cannot search photos: go back to the real-photo model
        end
        if ~isempty(S.model), return; end
        if ~exist(f, 'file'), f = fullfile(root, 'models', 'lpr_svm_model.mat'); end
        if exist(f, 'file')
            L = load(f);  S.model = L.model;
        else
            ok = false;
            sel = uiconfirm(fig, 'No trained SVM model found. Train one now (about 1 minute)?', ...
                            'SVM model', 'Options', {'Train', 'Cancel'}, 'DefaultOption', 1);
            if strcmp(sel, 'Train'), onTrain(); ok = ~isempty(S.model); end
        end
    end

    function onTrain()
        if exist(fullfile(root, 'models', 'lpr_svm_model_real.mat'), 'file')
            sel = uiconfirm(fig, ['The model trained with real photos is installed and used by this toolbox. ' ...
                'Training here builds a new model from computer fonts only: it cannot search whole photos and reads real plates worse. Train it anyway?'], ...
                'SVM model', 'Options', {'Keep current model', 'Train anyway'}, 'DefaultOption', 1, 'CancelOption', 1);
            if ~strcmp(sel, 'Train anyway'), return; end
        end
        d = uiprogressdlg(fig, 'Title', 'Training SVM', 'Message', ...
            'Rendering characters and training 630 binary SVMs - see the MATLAB command window.', 'Indeterminate', 'on');
        drawnow;
        try
            haveReal = exist(fullfile(root, 'models', 'lpr_svm_model_real.mat'), 'file') > 0;
            if haveReal, saveTo = fullfile(tempdir, 'lpr_svm_model_fonts.mat'); else, saveTo = ''; end      % never overwrite the installed models
            newModel = trainLPRModel('NPerClass', 200, 'HoldOut', false, 'SaveTo', saveTo);
            msg = sprintf('SVM trained: %d support vectors, training-set accuracy %.1f %%.', size(newModel.svm.SV, 1), 100 * newModel.report.trainAcc);
            if haveReal
                log_([msg ' This model uses computer fonts only and cannot search whole photos, so the real-photo model stays in use.']);
            else
                S.model = newModel;  log_(msg);
            end
        catch ME
            close(d);  uialert(fig, ME.message, 'Training failed');  return;
        end
        close(d);
    end

    function recognizeAllScripted()
        % scripted access: same as ticking "Find ALL plates" and pressing "Recognise plate"
        if isempty(S.I) || ~ensureModel(), return; end
        onRecognizeAll();
    end

    function onRecognizeAll()
        % every plate the plate SVM accepts (road scenes); small plates are marked unreliable
        S.crops = zeros(0, 4);
        fig.Pointer = 'watch';
        dlg = openBusy('Reading all plates', 'Searching the whole photo. A big photo with many cars can take a few minutes.');
        t0 = tic;
        try
            [out, unread] = recognizePlates(S.I, S.model, 'Consensus', plate.vote.Value, 'NightVision', plate.night.Value);
        catch ME
            closeDlg(dlg);  fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        closeDlg(dlg);
        fig.Pointer = 'arrow';
        S.lastRes = [];  S.plates = out;  S.unread = unread;
        tabs.SelectedTab = tabPlate;
        renderPlates(1);
        if isempty(out)
            msg = sprintf(['No plate could be read [%.1f s]. A plate needs about 100 pixels of width to be read; plates of 30 pixels or less ' ...
                           'cannot be found or read by any filter. Press Crop and drag a box around a car to look at it closely; for a dark photo tick "Night vision".'], toc(t0));
            if ~isempty(unread)
                msg = sprintf('%s %d plate-like region(s) were found (grey dashed boxes): look at them in the photo or take a closer picture.', msg, numel(unread));
            end
            log_([{msg}; plateLines()]);
        else
            log_([{sprintf('%d plate(s) read, %d plate-like region(s) not read [%.1f s]. The readings of small (orange) plates are often wrong. A car without a number? Press Crop and drag a box around it.', numel(out), numel(unread), toc(t0))}; plateLines()]);
        end
        if ~isempty(S.truth), infoBox.Value = [infoBox.Value(:); {['Ground truth (the photo of the list): ' S.truth]}]; end
    end

    function d = openBusy(ttl, msg)
        d = [];
        try d = uiprogressdlg(fig, 'Title', ttl, 'Indeterminate', 'on', 'Message', msg); catch, end %#ok<CTCH>
        drawnow;
    end

    function closeDlg(d)
        if ~isempty(d), try close(d); catch, end, end %#ok<CTCH>
    end

    function lines = plateLines()
        % one text line per plate and per grey region, for the box at the bottom of the left panel
        out = S.plates;  unread = S.unread;
        lines = cell(0, 1);
        for k = 1:numel(out)
            note = '';
            if ~out(k).reliable, note = '  (plate too small: reading unreliable)'; end
            if out(k).lines == 2, note = [note '  (two-line plate: upper and lower row)']; end %#ok<AGROW>
            lines{end+1, 1} = sprintf('%d) %s   plate %d px wide, plate-SVM score %.2f%s', k, out(k).text, out(k).width, out(k).score, note); %#ok<AGROW>
        end
        for k = 1:numel(unread)
            lines{end+1, 1} = sprintf('?%d) plate-like region, %d px wide, not read (too small, blurred, or glare)', k, unread(k).width); %#ok<AGROW>
        end
    end

    function renderPlates(sel)
        % the photo with every plate box and its number above it, the pick list, "Result", the gallery and the big number
        out = S.plates;  unread = S.unread;
        ttl = sprintf('%d plate(s) read, %d plate-like region(s) not read', numel(out), numel(unread));
        if ~isempty(S.crops), ttl = sprintf('%s, %d crop(s) (blue)', ttl, size(S.crops, 1)); end
        showImage(axOrig, S.I, ttl);
        hold(axOrig, 'on');
        for k = 1:size(S.crops, 1)                                 % the crops, like the frame of a photo editor
            b = S.crops(k, :);
            rectangle(axOrig, 'Position', b, 'EdgeColor', [0.2 0.85 1], 'LineWidth', 1.5, 'LineStyle', '--', 'PickableParts', 'none');
        end
        S.boxH = gobjects(1, numel(out));
        for k = 1:numel(out)
            if out(k).reliable, col = [1 0.1 0.1]; else, col = [1 0.6 0]; end
            S.boxH(k) = rectangle(axOrig, 'Position', out(k).box, 'EdgeColor', col, 'LineWidth', 2, 'PickableParts', 'none');
            text(axOrig, out(k).box(1), max(out(k).box(2) - 3, 1), sprintf('%d: %s', k, out(k).text), 'Color', [1 1 0], 'VerticalAlignment', 'bottom', ...
                 'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [0 0 0], 'Interpreter', 'none', 'Clipping', 'on', 'PickableParts', 'none');
        end
        for k = 1:numel(unread)                                    % plate-like regions that could not be read
            rectangle(axOrig, 'Position', unread(k).box, 'EdgeColor', [0.75 0.75 0.75], 'LineWidth', 1.5, 'LineStyle', '--', 'PickableParts', 'none');
            text(axOrig, unread(k).box(1), max(unread(k).box(2) - 3, 1), sprintf('?%d', k), 'Color', [0.85 0.85 0.85], 'FontSize', 9, 'VerticalAlignment', 'bottom', ...
                 'Interpreter', 'none', 'Clipping', 'on', 'PickableParts', 'none');
        end
        hold(axOrig, 'off');
        items = arrayfun(@(k) sprintf('%d: %s', k, out(k).text), 1:numel(out), 'UniformOutput', false);
        if isempty(items), plate.pick.Items = {'-'};  plate.pick.ItemsData = {0};  plate.pick.Value = 0;  sel = 0;
        else, plate.pick.Items = items;  plate.pick.ItemsData = num2cell(1:numel(out));  sel = min(max(sel, 1), numel(out));  plate.pick.Value = sel; end
        showPlateDetail(sel);
        showGallery(out, unread);
        if isempty(out)
            plate.result.Text = '0 plates';  plate.result.FontSize = 26;
        else
            plate.result.Text = strjoin({out.text}, '   ');  plate.result.FontSize = 26 - 8 * (numel(out) > 1) - 4 * (numel(out) > 3);
        end
    end

    function onPickPlate()
        showPlateDetail(plate.pick.Value);
    end

    function showPlateDetail(k)
        % "Result": the plate k of the last search cut out and segmented, the number above it; its box on the photo gets a thick frame
        out = S.plates;
        for q = 1:numel(S.boxH)
            if isgraphics(S.boxH(q)), S.boxH(q).LineWidth = 2 + 3 * (q == k); end
        end
        if isempty(out) || k < 1 || k > numel(out)
            clearResult();  return
        end
        o = out(k);
        if ~isempty(o.segPlate) && ~isempty(o.charBoxes)
            showImage(axRes, o.segPlate, sprintf('Plate %d: %s   (segmented, %d characters)', k, o.text, size(o.charBoxes, 1)));
            hold(axRes, 'on');
            for q = 1:size(o.charBoxes, 1)
                rectangle(axRes, 'Position', o.charBoxes(q, :), 'EdgeColor', [0 0.8 0], 'LineWidth', 1.5);
            end
            hold(axRes, 'off');
        else
            b = round(o.box);  I = S.I;
            showImage(axRes, I(max(1, b(2)):min(size(I, 1), b(2) + b(4) - 1), max(1, b(1)):min(size(I, 2), b(1) + b(3) - 1), :), ...
                      sprintf('Plate %d: %s', k, o.text));
        end
    end

    function showGallery(out, unread)
        % one tile per plate: its number above, the plate with its surroundings in the middle, the characters the SVM saw below
        % (red frame = readable size, orange = small and unreliable, grey = plate-like region that was not read); a click chooses the plate
        resetAux();
        S.gal = [];
        nO = numel(out);  nU = numel(unread);  nAll = nO + nU;
        if nAll == 0, return; end
        I = S.I;  if size(I, 3) == 1, I = repmat(I, [1 1 3]); end
        perRow = 5;  ph = 104;  pw = 156;  sh = 26;  lh = 24;  g = 8;
        th = lh + ph + sh;
        nR = ceil(nAll / perRow);
        canvas = 0.08 * ones(nR * (th + g) + g, perRow * (pw + g) + g, 3);
        xs = zeros(nAll, 1);  ys = xs;  labels = cell(1, nAll);
        for k = 1:nAll
            if k <= nO, b = out(k).box;  labels{k} = sprintf('%d: %s', k, out(k).text);
            else, b = unread(k - nO).box;  labels{k} = sprintf('?%d: not read', k - nO); end
            reg = round(contextBox(b, size(I, 2), size(I, 1), pw / ph));
            x0r = max(1, reg(1));  y0r = max(1, reg(2));  x1r = min(size(I, 2), reg(1) + reg(3) - 1);  y1r = min(size(I, 1), reg(2) + reg(4) - 1);
            crop = I(y0r:y1r, x0r:x1r, :);
            if k > nO, col = [0.6 0.6 0.6]; elseif out(k).reliable, col = [1 0.1 0.1]; else, col = [1 0.6 0]; end
            sc = min((ph - 4) / size(crop, 1), (pw - 4) / size(crop, 2));
            crop = imResize(crop, sc, 'bicubic');
            crop = frameBox(crop, [(b(1) - x0r + 1) * sc, (b(2) - y0r + 1) * sc, b(3) * sc, b(4) * sc], col);       % the plate inside its picture
            row = ceil(k / perRow);  cc = mod(k - 1, perRow) + 1;
            y0 = g + (row - 1) * (th + g);  x0 = g + (cc - 1) * (pw + g);
            tile = repmat(reshape(col, 1, 1, 3), ph, pw);
            tile(3:ph-2, 3:pw-2, :) = 0.08;
            oy = floor((ph - size(crop, 1)) / 2);  ox = floor((pw - size(crop, 2)) / 2);
            tile(oy+1:oy+size(crop, 1), ox+1:ox+size(crop, 2), :) = min(max(crop, 0), 1);
            canvas(y0+lh+1:y0+lh+ph, x0+1:x0+pw, :) = tile;
            if k <= nO && ~isempty(out(k).chars)                                           % what the SVM saw: the 32 x 32 characters
                strip = [];
                for q = 1:numel(out(k).chars), strip = [strip, out(k).chars{q}, zeros(32, 3)]; end %#ok<AGROW>
                strip = imResize(1 - strip, min((sh - 4) / size(strip, 1), (pw - 4) / size(strip, 2)), 'bilinear');
                canvas(y0+lh+ph+2:y0+lh+ph+1+size(strip, 1), x0+2:x0+1+size(strip, 2), :) = repmat(min(max(strip, 0), 1), [1 1 3]);
            end
            xs(k) = x0;  ys(k) = y0 + lh / 2;
        end
        axis(axAux, 'on');
        hI = showImage(axAux, canvas, 'Plates: number above, SVM characters below (red = readable, orange = small, grey = not read). Click one to choose it.');
        hI.ButtonDownFcn = @(~, e) onGalleryClick(e);
        S.gal = struct('perRow', perRow, 'pw', pw, 'th', th, 'g', g, 'nO', nO);
        hold(axAux, 'on');
        for k = 1:nAll
            text(axAux, xs(k) + 3, ys(k), labels{k}, 'Color', [1 1 0], 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none', 'VerticalAlignment', 'middle', 'PickableParts', 'none');
        end
        hold(axAux, 'off');
    end

    function onGalleryClick(e)
        if isempty(S.gal), return; end
        q = S.gal;
        c = floor((e.IntersectionPoint(1) - q.g) / (q.pw + q.g)) + 1;
        r = floor((e.IntersectionPoint(2) - q.g) / (q.th + q.g)) + 1;
        k = (r - 1) * q.perRow + c;
        if c < 1 || c > q.perRow || r < 1 || k > q.nO, return; end
        plate.pick.Value = k;
        showPlateDetail(k);
    end

    function r = contextBox(b, W, H, aspect)
        % the picture of a tile: the plate with its surroundings (about 3 plate widths), as wide as high x aspect
        w = max(3 * b(3), 90);  h = w / aspect;
        if h < 2.2 * b(4), h = 2.2 * b(4);  w = h * aspect; end
        w = min(w, W);  h = min(h, H);
        x0 = min(max(1, b(1) + b(3) / 2 - w / 2), W - w + 1);  y0 = min(max(1, b(2) + b(4) / 2 - h / 2), H - h + 1);
        r = [x0, y0, w, h];
    end

    function C = frameBox(C, bx, col)
        % draw a 1 pixel frame [x y w h] into the picture C (the plate inside its surroundings)
        x0 = max(1, round(bx(1)));  y0 = max(1, round(bx(2)));
        x1 = min(size(C, 2), round(bx(1) + bx(3)));  y1 = min(size(C, 1), round(bx(2) + bx(4)));
        if x1 <= x0 || y1 <= y0, return; end
        for ch = 1:3
            C(y0, x0:x1, ch) = col(ch);  C(y1, x0:x1, ch) = col(ch);  C(y0:y1, x0, ch) = col(ch);  C(y0:y1, x1, ch) = col(ch);
        end
    end

% ------------------------------- crop tool ------------------------------------
    function onCropToggle(on)
        S.cropMode = logical(on);
        if S.cropMode
            try axOrig.Interactions = []; catch, end                   %#ok<CTCH> dragging must not pan or zoom the photo
            if isempty(S.I)
                log_('Crop is on. Open an image first, then drag a rectangle around ONE car or plate on the photo.');
            else
                log_('Crop is on: drag a rectangle around ONE car or plate on the photo (top left). Release the mouse to read it.');
            end
        else
            try axOrig.Interactions = axInter; catch, end              %#ok<CTCH>
            fig.Pointer = 'arrow';
            stopDrag();
        end
    end

    function onClearCrops()
        S.crops = zeros(0, 4);
        if isempty(S.I), return; end
        if ~isempty(S.plates) || ~isempty(S.unread)
            renderPlates(max(1, plate.pick.Value));
        else
            showImage(axOrig, S.I, 'Input');
        end
        log_('The crop frames are removed. The plates found stay in the list.');
    end

    function p = photoPoint(clamp)
        % mouse position in photo pixels; [] when it is not over the photo (clamp = true: the nearest point of the photo)
        p = [];
        if isempty(S.I), return; end
        cp = axOrig.CurrentPoint;
        [H, W, ~] = size(S.I);
        x = cp(1, 1);  y = cp(1, 2);
        if clamp
            p = [min(max(x, 0.5), W + 0.5), min(max(y, 0.5), H + 0.5)];
        elseif x >= 0.5 && x <= W + 0.5 && y >= 0.5 && y <= H + 0.5
            p = [x y];
        end
    end

    function onMouseDown()
        if ~S.cropMode, return; end
        p = photoPoint(false);
        if ~isempty(p), startDrag(p); end
    end

    function onMouseMove()
        if ~S.cropMode || isempty(S.I), return; end
        if drag.on
            moveDrag(photoPoint(true));
        else
            ptr = 'arrow';
            if ~isempty(photoPoint(false)), ptr = 'cross'; end
            if ~strcmp(fig.Pointer, ptr) && ~strcmp(fig.Pointer, 'watch'), fig.Pointer = ptr; end
        end
    end

    function onMouseUp()
        if ~drag.on, return; end
        finishDrag(photoPoint(true));
    end

    function startDrag(p)
        stopDrag();
        drag.on = true;  drag.p0 = p;  drag.p1 = p;
        xl = axOrig.XLim;  yl = axOrig.YLim;
        cy = [0.2 0.85 1];
        hold(axOrig, 'on');
        d.dim = gobjects(1, 4);
        for q = 1:4
            d.dim(q) = patch(axOrig, 'XData', [0 0 0 0], 'YData', [0 0 0 0], 'FaceColor', 'k', 'FaceAlpha', 0.55, 'EdgeColor', 'none', 'PickableParts', 'none');
        end
        d.frame = patch(axOrig, 'XData', [0 0 0 0], 'YData', [0 0 0 0], 'FaceColor', 'none', 'EdgeColor', cy, 'LineWidth', 2, 'PickableParts', 'none');
        d.thirds = gobjects(1, 4);
        for q = 1:4
            d.thirds(q) = line(axOrig, [0 0], [0 0], 'Color', [1 1 1 0.5], 'LineWidth', 0.5, 'PickableParts', 'none');
        end
        d.handles = line(axOrig, nan, nan, 'LineStyle', 'none', 'Marker', 's', 'MarkerFaceColor', [1 1 1], 'MarkerEdgeColor', cy, 'MarkerSize', 7, 'PickableParts', 'none');
        d.lab = text(axOrig, 0, 0, '', 'Color', [1 1 1], 'BackgroundColor', [0 0 0], 'FontSize', 11, 'FontWeight', 'bold', ...
                     'VerticalAlignment', 'top', 'Margin', 2, 'Clipping', 'on', 'PickableParts', 'none');
        hold(axOrig, 'off');
        axOrig.XLim = xl;  axOrig.YLim = yl;
        drag.h = d;
        moveDrag(p);
    end

    function moveDrag(p1)
        if ~drag.on || isempty(p1) || ~isstruct(drag.h) || ~isgraphics(drag.h.frame), return; end
        drag.p1 = p1;
        [H, W, ~] = size(S.I);
        xa = min(drag.p0(1), p1(1));  xb = max(drag.p0(1), p1(1));  ya = min(drag.p0(2), p1(2));  yb = max(drag.p0(2), p1(2));
        xm = (xa + xb) / 2;  ym = (ya + yb) / 2;  x0 = 0.5;  x1 = W + 0.5;  y0 = 0.5;  y1 = H + 0.5;
        d = drag.h;
        set(d.dim(1), 'XData', [x0 x1 x1 x0], 'YData', [y0 y0 ya ya]);               % the part outside the crop is dimmed
        set(d.dim(2), 'XData', [x0 x1 x1 x0], 'YData', [yb yb y1 y1]);
        set(d.dim(3), 'XData', [x0 xa xa x0], 'YData', [ya ya yb yb]);
        set(d.dim(4), 'XData', [xb x1 x1 xb], 'YData', [ya ya yb yb]);
        set(d.frame, 'XData', [xa xb xb xa], 'YData', [ya ya yb yb]);
        for q = 1:2                                                                   % rule-of-thirds guides
            set(d.thirds(q), 'XData', (xa + q * (xb - xa) / 3) * [1 1], 'YData', [ya yb]);
            set(d.thirds(2 + q), 'XData', [xa xb], 'YData', (ya + q * (yb - ya) / 3) * [1 1]);
        end
        set(d.handles, 'XData', [xa xm xb xa xb xa xm xb], 'YData', [ya ya ya ym ym yb yb yb]);
        set(d.lab, 'Position', [xa + 3, ya + 3, 0], 'String', sprintf('%d x %d px', round(xb - xa), round(yb - ya)));
        drawnow limitrate;
    end

    function stopDrag()
        if isstruct(drag.h)
            f = fieldnames(drag.h);
            for q = 1:numel(f), v = drag.h.(f{q}); delete(v(isgraphics(v))); end
        end
        drag.h = gobjects(0);  drag.on = false;
    end

    function finishDrag(p1)
        b = dragBox(drag.p0, p1);
        stopDrag();
        if b(3) < 24 || b(4) < 16
            log_('That crop is too small. Drag a rectangle of at least 24 x 16 pixels around the car or plate.');
            return
        end
        readCropBox(b);
    end

    function b = dragBox(p0, p1)
        % [x y w h] in pixels of the photo from two corner points
        xa = min(p0(1), p1(1));  ya = min(p0(2), p1(2));
        b = [max(1, round(xa)), max(1, round(ya)), round(abs(p1(1) - p0(1))), round(abs(p1(2) - p0(2)))];
    end

    function dragCropScripted(p0, p1, finish)
        % scripted access: the same steps as a mouse drag from p0 to p1 (photo pixels); finish = false leaves the drag frame on the photo
        if nargin < 3, finish = true; end
        if isempty(S.I), return; end
        S.cropMode = true;
        startDrag(p0);
        moveDrag((p0 + p1) / 2);
        moveDrag(p1);
        if finish, finishDrag(p1); end
    end

    function readCropBox(b)
        % cut the rectangle b = [x y w h] out of the photo, enlarge it, read every plate in it and add them to the list
        if isempty(S.I) || ~ensureModel(), return; end
        [H, W, ~] = size(S.I);
        x0 = max(1, round(b(1)));  y0 = max(1, round(b(2)));
        x1 = min(W, x0 + round(b(3)) - 1);  y1 = min(H, y0 + round(b(4)) - 1);
        b = [x0, y0, x1 - x0 + 1, y1 - y0 + 1];
        S.crops(end+1, :) = b;
        n = size(S.crops, 1);
        fig.Pointer = 'watch';
        dlg = openBusy(sprintf('Reading crop %d', n), 'Cutting out the area, enlarging it and reading every plate in it.');
        try
            [o, u, info] = readCrop(S.I, S.model, b, 'NightVision', plate.night.Value);
        catch ME
            closeDlg(dlg);  fig.Pointer = 'arrow';  S.crops(end, :) = [];  uialert(fig, ME.message, 'Crop failed');  return;
        end
        closeDlg(dlg);
        fig.Pointer = 'arrow';
        S.lastRes = [];
        sel = mergeCrop(o, u);
        tabs.SelectedTab = tabPlate;
        renderPlates(sel);
        if isempty(o)                                              % nothing read: show what was cut out
            showImage(axRes, S.I(b(2):b(2) + b(4) - 1, b(1):b(1) + b(3) - 1, :), sprintf('Crop %d (%d x %d px): no plate read', n, b(3), b(4)));
        end
        head = sprintf('Crop %d: %d x %d px, enlarged %.1f times [%.1f s].', n, b(3), b(4), info.scale, info.seconds);
        if isempty(o)
            if isempty(u)
                head = sprintf(['%s No plate could be read here. A plate needs about 100 pixels of width in the photo (40 at the very least); ' ...
                                'a 30 pixel plate has no characters to read, however much it is enlarged. Take a closer photo of this car.'], head);
            else
                head = sprintf('%s A plate-like region was found (grey dashed box) but it is too small or blurred to read.', head);
            end
        else
            head = sprintf('%s Read: %s.', head, strjoin({o.text}, ', '));
            if any(~[o.reliable]), head = [head ' Small (orange) plates are often misread.']; end
        end
        log_([{head}; plateLines()]);
    end

    function sel = mergeCrop(o, u)
        % the plates of a crop join the list: a plate seen before keeps the reading with the higher vote confidence
        sel = 1;  newIdx = [];
        if ~isstruct(S.plates), S.plates = o(zeros(1, 0)); end       % the list is [] before the first reading
        for q = 1:numel(o)
            dup = 0;
            for j = 1:numel(S.plates)
                if boxOverlap(o(q).box, S.plates(j).box) > 0.5, dup = j;  break; end
            end
            if dup == 0
                S.plates(end+1) = o(q);  newIdx(end+1) = numel(S.plates); %#ok<AGROW>
            else
                if betterReading(o(q), S.plates(dup)), S.plates(dup) = o(q); end
                newIdx(end+1) = dup; %#ok<AGROW>
            end
        end
        keepU = true(1, numel(S.unread));                            % grey boxes under a plate are that plate
        for j = 1:numel(S.unread)
            for k = 1:numel(S.plates)
                if boxOverlap(S.unread(j).box, S.plates(k).box) > 0.5, keepU(j) = false; end
            end
        end
        if isempty(S.unread), S.unread = u(zeros(1, 0)); end
        S.unread = S.unread(keepU);
        for q = 1:numel(u)
            over = false;
            for k = 1:numel(S.plates), if boxOverlap(u(q).box, S.plates(k).box) > 0.5, over = true; end, end
            for k = 1:numel(S.unread), if boxOverlap(u(q).box, S.unread(k).box) > 0.5, over = true; end, end
            if ~over, S.unread(end+1) = u(q); end %#ok<AGROW>
        end
        if ~isempty(newIdx), sel = newIdx(1); end
    end

    function yes = betterReading(a, b)
        % the new reading a replaces the old one b of the same plate when its vote confidence is higher; but a reading that
        % contains the other one and has more characters wins (T935AK797 against T935AK7: the small region digits lower the mean
        % confidence, they must not decide against the full number)
        ta = strrep(a.text, ' ', '');  tb = strrep(b.text, ' ', '');
        if numel(ta) > numel(tb) && contains(ta, tb), yes = true;  return; end
        if numel(tb) > numel(ta) && contains(tb, ta), yes = false;  return; end
        yes = a.conf >= b.conf;
    end

    function v = boxOverlap(a, b)
        % intersection over the area of the smaller box
        x1 = max(a(1), b(1));  y1 = max(a(2), b(2));
        x2 = min(a(1) + a(3), b(1) + b(3));  y2 = min(a(2) + a(4), b(2) + b(4));
        v = max(0, x2 - x1) * max(0, y2 - y1) / max(1, min(a(3) * a(4), b(3) * b(4)));
    end

    function onRemovePlate()
        k = plate.pick.Value;
        if isempty(S.plates) || k < 1 || k > numel(S.plates), return; end
        gone = S.plates(k).text;
        S.plates(k) = [];
        renderPlates(min(k, numel(S.plates)));
        log_([{sprintf('%s removed from the list.', gone)}; plateLines()]);
    end

    function onCopyPlates()
        if isempty(S.plates), return; end
        txt = strjoin({S.plates.text}, newline);
        try
            clipboard('copy', txt);
            log_(sprintf('Copied %d plate number(s) to the clipboard.', numel(S.plates)));
        catch
            log_('The clipboard is not available here.');
        end
    end

    function onRecognize()
        if isempty(S.I), uialert(fig, 'Open an image first.', 'No image'); return; end
        if ~ensureModel(), return; end
        if S.useFilters && ~isempty(S.orig) && ~isempty(chainFromPanel())      % filters are active: "Recognise plate" reads the filtered photo
            S.useFilters = false;
            cleaner = onCleanup(@() setUseFilters());
            onRecognizeFiltered();
            return
        end
        if plate.all.Value, onRecognizeAll(); return; end
        fig.Pointer = 'watch';  drawnow;
        t0 = tic;
        try
            res = recognizePlate(S.I, S.model, 'Format', plate.format.Value, 'Polarity', plate.polarity.Value, 'Consensus', plate.vote.Value);
        catch ME
            fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        fig.Pointer = 'arrow';
        S.lastRes = res;
        tabs.SelectedTab = tabPlate;
        showImage(axOrig, S.I, 'Input and detected plate');
        S.plates = [];  S.unread = [];  S.crops = zeros(0, 4);  S.boxH = gobjects(0);  S.gal = [];
        plate.pick.Items = {'-'};  plate.pick.ItemsData = {0};  plate.pick.Value = 0;
        if res.found && ~isempty(res.bbox)
            rectangle(axOrig, 'Position', res.bbox, 'EdgeColor', 'r', 'LineWidth', 2);
            text(axOrig, res.bbox(1), max(res.bbox(2) - 3, 1), res.text, 'Color', [1 1 0], 'VerticalAlignment', 'bottom', 'FontSize', 12, ...
                 'FontWeight', 'bold', 'BackgroundColor', [0 0 0], 'Interpreter', 'none', 'Clipping', 'on');          % the number above the plate
        end
        if res.found
            s = res.segDebug;
            showImage(axRes, s.plate, sprintf('Segmented plate: %s   (%d characters)', res.text, numel(res.chars)));
            for k = 1:size(res.boxes, 1)
                rectangle(axRes, 'Position', res.boxes(k,:), 'EdgeColor', [0 0.8 0], 'LineWidth', 1.5);
            end
            strip = [];
            for k = 1:numel(res.chars), strip = [strip, res.chars{k}, zeros(32, 4)]; end %#ok<AGROW>
            resetAux();  axis(axAux, 'on');
            showImage(axAux, 1 - strip, 'Normalised characters (32x32) fed to the SVM');
            title(axAux, {['SVM reads: ' res.text], 'normalised characters (32x32) fed to the SVM'}, 'FontWeight', 'bold', 'Interpreter', 'none');
            plate.result.Text = res.text;  plate.result.FontSize = 26;
            msg = sprintf('Plate read: %s   (mean vote confidence %.0f %%)  [%.2f s]', res.text, 100 * mean(res.conf), toc(t0));
            if isequal(res.bbox, [1 1 size(S.I, 2) size(S.I, 1)])
                msg = sprintf('%s\n(The photo was read as a plate close-up: no search for the plate was needed.)', msg);
            elseif res.bbox(3) < 90
                msg = sprintf(['%s\nWARNING: the detected plate is only %d pixels wide. Below about 100 pixels the characters are too blurry ' ...
                               'for this system, so the reading is probably wrong. Use a closer photo, or press Crop and drag a box around one car.'], msg, round(res.bbox(3)));
            end
            if res.rectified
                msg = sprintf('%s\n(The plate was seen at an angle: it was straightened first, perspective correction by a homography.)', msg);
            end
            if ~isempty(S.truth), msg = sprintf('%s\nGround truth: %s', msg, S.truth); end
            log_(msg);
            S.result = repmat(s.plate, [1 1 3]);
        else
            clearResult();  resetAux();  axis(axAux, 'off');
            plate.result.Text = '?';
            if ~isempty(res.guess) && startsWith(res.reason, 'plate too small')
                rectangle(axOrig, 'Position', res.guess, 'EdgeColor', [1 0.6 0], 'LineWidth', 2, 'LineStyle', '--');
                log_(sprintf(['Plate located but too small to read: %d px wide (dashed orange box), at least %d px are needed. ' ...
                              'Use a closer photo, or press Crop and drag a box around the car.'], round(res.guess(3)), 40));
            else
                msg = 'No plate found.';
                if ~isempty(res.reason), msg = sprintf('No plate found (%s).', res.reason); end
                log_([msg ' This system needs a plate that is at least ~100 pixels wide with 4 or more separable characters. ' ...
                      'Try a closer photo, press Crop and drag a box around one vehicle, or set the character colour. ' ...
                      'For a dark photo tick "Night vision".']);
            end
        end
    end

    function onPipeline()
        if isempty(S.lastRes), onRecognize(); end
        if isempty(S.lastRes), return; end
        showPipeline(S.I, S.lastRes);
    end

    function clearResult()
        % an empty "Result" picture: no axis numbers, only the title
        cla(axRes, 'reset');
        set(axRes, 'XTick', [], 'YTick', [], 'Box', 'on');
        title(axRes, 'Result', 'FontWeight', 'normal');
    end

    function resetAux()
        % clear the lower axes completely (plots, labels and legend of the last view)
        legend(axAux, 'off');
        cla(axAux, 'reset');
        axis(axAux, 'off');
    end

    function msg = imageErrorText(ME, f)
        % friendly message for formats MATLAB cannot read (Google often saves .webp)
        [~, ~, ext] = fileparts(f);
        if any(strcmpi(ext, {'.webp', '.avif', '.jxl', '.heic'}))
            msg = ['MATLAB cannot read ' ext ' images. Open the file in Paint and use File > Save as > JPEG picture, ' ...
                   'or take a screenshot (Win+Shift+S) and save it as PNG, then open that file.'];
        else
            msg = ['This file could not be read as an image (' ext '). Use JPG, PNG, BMP or TIF. Details: ' ME.message];
        end
    end

    function s = getState()
        s = S;
    end

    function log_(msg)
        if ischar(msg), msg = strsplit(msg, newline); end
        infoBox.Value = msg;
        drawnow limitrate;
    end
end
