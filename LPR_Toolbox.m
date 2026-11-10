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
%                     scene, "Car by car" cuts every car out and reads it too, "Night vision" searches a brightened copy of a dark photo;
%                     the number of every plate is written above its box, above its picture and above the characters the SVM saw.
%   The original and the result are shown side by side. "Use result as input"
%   chains operations (e.g. equalise, then Canny).
%   The panel on the right ("Pre-filters") filters the ORIGINAL photo with up to four filters
%   (resolution, convolution, mean / Gaussian / median / bilateral, sharpening, deblurring,
%   brightness and contrast, local histogram equalisation, illumination, frequency domain),
%   with a choice of border padding. "Enlarge text" shows the explanation in a big window. "Suggest filters" measures the photo and proposes a chain,
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
S.model = [];  S.tpl = [];  S.truth = '';  S.lastRes = [];  S.realIdx = 0;  S.roi = [];
S.filtered = [];  S.filterNote = {};  S.useFilters = true;
S.plates = [];  S.unread = [];  S.cars = [];
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
main.ColumnWidth = {300, '1x', 360};  main.Padding = [8 8 8 8];

left = uigridlayout(main, [3 1]);
left.RowHeight = {170, '1x', 74};  left.Padding = [0 0 0 0];

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
ui = repmat(struct('idx', [], 'dd', [], 'lbl', [], 'sld', []), 1, 3);
for m = 1:3
    t = uitab(tabs, 'Title', names{m});
    ui(m) = buildOpTab(t, m);
end
tabPlate = uitab(tabs, 'Title', names{4});
plate = buildPlateTab(tabPlate);

infoBox = uitextarea(left, 'Editable', 'off', 'Value', {'Open an image or press "Synthetic car photo".'});

right = uigridlayout(main, [2 2]);
right.RowHeight = {'1.6x', '1x'};  right.Padding = [0 0 0 0];
axOrig = uiaxes(right);  axRes = uiaxes(right);
axAux  = uiaxes(right);  axAux.Layout.Row = 2;  axAux.Layout.Column = [1 2];
cla(axOrig); cla(axRes); resetAux();
axis(axAux, 'off');
fp = uipanel(main, 'Title', 'Pre-filters: filter the photo, then recognise again');
filt = buildFilterPanel(fp);

% ------------------------------- public handles ------------------------------
app.fig = fig;
app.loadImage  = @loadImage;
app.applyByName = @applyByName;
app.recognize  = @onRecognize;
app.realSample = @onRealSample;
app.recognizeAll = @recognizeAllScripted;
app.state      = @getState;
app.setFilters = @setFiltersScripted;
app.suggestFilters = @onSuggestFilters;
app.previewFilters = @onPreviewFilters;
app.recognizeFiltered = @onRecognizeFiltered;
app.compareFilters = @onCompareFilters;
app.clearFilters = @onClearFilters;
app.showPlate  = @showPlateDetail;
app.openFile = @openFileScripted;
app.enlargeText = @onEnlarge;
app.operations = ops;

% ============================== construction ================================
    function h = buildFilterPanel(parent)
        g = uigridlayout(parent, [12 1]);
        g.RowHeight = {48, 28, 26, 54, 54, 54, 54, 54, 28, 30, 28, '1x'};
        g.Padding = [6 6 6 6];  g.RowSpacing = 4;  g.Scrollable = 'on';
        uilabel(g, 'Text', 'Pick up to four filters yourself (they run in this order on the ORIGINAL photo). With no filter ticked the original photo is read.', 'WordWrap', 'on');
        uibutton(g, 'push', 'Text', 'Enlarge text', 'ButtonPushedFcn', @(~, ~) onEnlarge(), ...
                 'Tooltip', 'Show the text of the box at the bottom in a big window');
        pr = uigridlayout(g, [1 2]);  pr.Padding = [0 0 0 0];  pr.ColumnWidth = {110, '1x'};
        uilabel(pr, 'Text', 'Border (padding):');
        h.pad = uidropdown(pr, 'Items', {'replicate', 'symmetric', 'zero'}, 'Value', 'replicate', ...
                           'Tooltip', 'How the spatial filters fill in pixels outside the picture (edge effect)');
        h.on = gobjects(1, 4);  h.dd = gobjects(1, 4);
        h.l1 = gobjects(1, 4);  h.p1 = gobjects(1, 4);  h.l2 = gobjects(1, 4);  h.p2 = gobjects(1, 4);
        for k = 1:4
            sg = uigridlayout(g, [2 4]);
            sg.RowHeight = {26, 26};  sg.ColumnWidth = {'1x', 56, '1x', 56};  sg.Padding = [0 0 0 0];  sg.RowSpacing = 2;  sg.ColumnSpacing = 4;
            top = uigridlayout(sg, [1 2]);  top.Layout.Row = 1;  top.Layout.Column = [1 4];
            top.ColumnWidth = {78, '1x'};  top.Padding = [0 0 0 0];
            h.on(k) = uicheckbox(top, 'Text', sprintf('Filter %d', k), 'Value', false, ...
                                 'Tooltip', 'Tick = use this filter. Choose the filter in the list on the right.');
            h.dd(k) = uidropdown(top, 'Items', [{'(none)'}, {fops.name}], 'ItemsData', num2cell(0:numel(fops)), 'Value', 0, ...
                                 'ValueChangedFcn', @(~, ~) onFilterChanged(k, true));
            h.l1(k) = uilabel(sg, 'Text', '', 'Visible', 'off', 'HorizontalAlignment', 'right');
            h.p1(k) = uieditfield(sg, 'numeric', 'Value', 0, 'Visible', 'off');
            h.l2(k) = uilabel(sg, 'Text', '', 'Visible', 'off', 'HorizontalAlignment', 'right');
            h.p2(k) = uieditfield(sg, 'numeric', 'Value', 0, 'Visible', 'off');
        end
        kg = uigridlayout(g, [2 2]);
        kg.RowHeight = {24, 24};  kg.ColumnWidth = {100, '1x'};  kg.Padding = [0 0 0 0];  kg.RowSpacing = 2;
        uilabel(kg, 'Text', 'Own kernel:');
        h.preset = uidropdown(kg, 'Items', kernelPresets(1), 'ItemsData', num2cell(1:6), 'Value', 1, ...
                              'ValueChangedFcn', @(~, ~) onKernelPreset());
        uilabel(kg, 'Text', 'Matrix:');
        h.kernel = uieditfield(kg, 'text', 'Value', kernelPresets(2, 1), ...
                               'Tooltip', 'odd size, e.g. [0 -1 0; -1 5 -1; 0 -1 0]; used by "Convolution with my own kernel"');
        pg1 = uigridlayout(g, [1 2]);  pg1.Padding = [0 0 0 0];  pg1.ColumnSpacing = 5;
        uibutton(pg1, 'push', 'Text', 'Suggest filters', 'ButtonPushedFcn', @(~, ~) onSuggestFilters(), ...
                 'Tooltip', 'Measure the photo (brightness, contrast, dots, noise) and propose filters');
        uibutton(pg1, 'push', 'Text', 'Preview filtered', 'ButtonPushedFcn', @(~, ~) onPreviewFilters(), ...
                 'Tooltip', 'Show the filtered photo and the histograms without reading the plate');
        uibutton(g, 'push', 'Text', 'Recognise on filtered photo', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onRecognizeFiltered());
        pg2 = uigridlayout(g, [1 2]);  pg2.Padding = [0 0 0 0];  pg2.ColumnSpacing = 5;
        uibutton(pg2, 'push', 'Text', 'Compare with original', 'ButtonPushedFcn', @(~, ~) onCompareFilters(), ...
                 'Tooltip', 'Read the original and the filtered photo and print both results');
        uibutton(pg2, 'push', 'Text', 'Remove filters', 'ButtonPushedFcn', @(~, ~) onClearFilters(), ...
                 'Tooltip', 'Go back to the original photo');
        h.report = uitextarea(g, 'Editable', 'off', 'FontSize', 13, 'Value', {'No filter chosen: the original photo is used. Pick filters above or press "Suggest filters".'});
    end

    function v = kernelPresets(what, k)
        names = {'Sharpen', 'Edge (Laplacian)', 'Box blur 3x3', 'Gaussian 3x3', 'Identity', 'Sobel (horizontal gradient)'};
        mats  = {'[0 -1 0; -1 5 -1; 0 -1 0]', '[1 1 1; 1 -8 1; 1 1 1]', '[1 1 1; 1 1 1; 1 1 1]/9', '[1 2 1; 2 4 2; 1 2 1]/16', ...
                 '[0 0 0; 0 1 0; 0 0 0]', '[-1 0 1; -2 0 2; -1 0 1]'};
        if what == 1, v = names; else, v = mats{k}; end
    end

    function h = buildOpTab(tab, m)
        g = uigridlayout(tab, [8 1]);
        g.RowHeight = {28, 20, 22, 20, 22, 20, 22, 32};  g.Padding = [6 6 6 6];  g.RowSpacing = 4;
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
        % rows: dd, (lbl, sld) x 3, button  -> reorder not needed, grid fills in creation order
        ui(m) = h; %#ok<NASGU>
        refreshParams(h, m);
    end

    function h = buildPlateTab(tab)
        g = uigridlayout(tab, [15 1]);
        g.RowHeight = {22, 28, 22, 28, 26, 26, 26, 26, 22, 32, 28, 32, 32, 32, '1x'};  g.Padding = [6 6 6 6];  g.RowSpacing = 5;
        uilabel(g, 'Text', 'Plate layout (optional): L = letter, D = digit');
        h.format = uieditfield(g, 'text', 'Value', '', 'Placeholder', 'e.g. LLL DDDD');
        uilabel(g, 'Text', 'Character colour');
        h.polarity = uidropdown(g, 'Items', {'auto', 'dark', 'bright'}, 'Value', 'auto');
        h.all = uicheckbox(g, 'Text', 'Find ALL plates (road scene with many cars)', 'Value', true);
        h.cars = uicheckbox(g, 'Text', 'Car by car: crop every car and read it too (slower)', 'Value', true, ...
                            'Tooltip', 'Every car is cut out around its plate or its tail lights, enlarged and searched again; cars whose plate was missed in the whole photo get a second chance');
        h.night = uicheckbox(g, 'Text', 'Night vision (dark photo)', 'Value', false, ...
                             'Tooltip', 'Removes the illumination, lifts the shadows and reduces noise, then searches this copy too');
        h.vote = uicheckbox(g, 'Text', 'Vote over filtered copies (slower, +3 % exact)', 'Value', false);
        h.carLabel = uilabel(g, 'Text', 'Vehicle: whole photo');
        pg = uigridlayout(g, [1 2]);  pg.Padding = [0 0 0 0];  pg.ColumnSpacing = 5;
        uibutton(pg, 'push', 'Text', 'Pick vehicle...', 'ButtonPushedFcn', @(~,~) onPickCar());
        uibutton(pg, 'push', 'Text', 'Whole photo', 'ButtonPushedFcn', @(~,~) onClearCar());
        sp = uigridlayout(g, [1 2]);  sp.Padding = [0 0 0 0];  sp.ColumnSpacing = 5;  sp.ColumnWidth = {70, '1x'};
        uilabel(sp, 'Text', 'Show plate:');
        h.pick = uidropdown(sp, 'Items', {'-'}, 'ItemsData', {0}, 'Value', 0, 'ValueChangedFcn', @(~, ~) onPickPlate(), ...
                            'Tooltip', 'After "Find ALL plates": the plate whose segmentation is shown in "Result"');
        uibutton(g, 'push', 'Text', 'Recognise plate', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) onRecognize());
        uibutton(g, 'push', 'Text', 'Show pipeline stages', 'ButtonPushedFcn', @(~,~) onPipeline());
        uibutton(g, 'push', 'Text', 'Train SVM model...', 'ButtonPushedFcn', @(~,~) onTrain());
        h.result = uilabel(g, 'Text', '', 'FontSize', 26, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'WordWrap', 'on');
    end

    function refreshParams(h, m)
        g = ops(h.dd.Value);
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
        S.orig = img;  S.I = img;  S.result = [];  S.lastRes = [];  S.roi = [];  S.filtered = [];  S.filterNote = {};  S.plates = [];  S.unread = [];  S.cars = [];
        try plate.carLabel.Text = 'Vehicle: whole photo'; catch, end   %#ok<CTCH>
        try setStagesFromChain([]);  filt.report.Value = {'A new photo is loaded: Filter 1 to Filter 4 were cleared.'}; catch, end   %#ok<CTCH>
        fileLabel.Text = sprintf('%s  (%d x %d)', label, size(img, 2), size(img, 1));
        showImage(axOrig, S.I, 'Original');
        cla(axRes);  resetAux();  axis(axAux, 'off');
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
        showImage(axOrig, S.I, 'Original');  cla(axRes);  resetAux();
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
        if g.module == 1, drawHistograms(S.I, S.result); else, resetAux(); axis(axAux, 'off'); end
        log_(sprintf('%s  [%.2f s]\n%s', g.name, toc(t0), info));
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
    end

    function onFilterChanged(k, showGuide)
        if nargin < 2, showGuide = false; end
        idx = filt.dd(k).Value;
        labs = {filt.l1(k), filt.l2(k)};  eds = {filt.p1(k), filt.p2(k)};
        if idx == 0
            filt.on(k).Value = false;
            for q = 1:2, labs{q}.Visible = 'off';  eds{q}.Visible = 'off'; end
            filt.dd(k).Tooltip = '';
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
        if showGuide                                              % explain the chosen filter
            filt.report.Value = [{op.name; ''}; helpLines(op)];
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

    function bf = onEnlarge()
        % the text of the filter panel in a big window with big letters
        txt = filt.report.Value;
        w = round(0.7 * scr(3));  hgt = round(0.75 * scr(4));
        bf = uifigure('Name', 'Filter panel text', 'Position', [round((scr(3) - w) / 2), round((scr(4) - hgt) / 2), w, hgt], 'Visible', fig.Visible);
        gl = uigridlayout(bf, [2 1]);  gl.RowHeight = {'1x', 34};
        uitextarea(gl, 'Editable', 'off', 'FontSize', 18, 'Value', txt);
        uibutton(gl, 'push', 'Text', 'Close', 'FontSize', 14, 'ButtonPushedFcn', @(~, ~) delete(bf));
    end

    function setStagesFromChain(chain)
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
            [F, rep] = applyPrefilters(S.orig, chain, 'Pad', filt.pad.Value, 'Kernel', K);
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
            filt.report.Value = {'No filter selected: the original photo is used.'};
        else
            filt.report.Value = [{sprintf('%d filter(s) on the original photo (%s padding):', numel(rep), filt.pad.Value)}, rep(:).'];
        end
        ok = true;
    end

    function onSuggestFilters()
        if isempty(S.orig), uialert(fig, 'Open an image first.', 'No image'); return; end
        fig.Pointer = 'watch';  drawnow;
        [chain, reasons, st] = suggestPrefilters(S.orig);
        fig.Pointer = 'arrow';
        setStagesFromChain(chain);
        lines = [{sprintf('Measured: median luminance %.2f, range %.2f, impulse dots %.1f %%, noise sigma %.3f, saturated %.1f %%.', ...
                          st.median, st.range, 100 * st.impulse, st.noise, 100 * st.saturated)}, reasons(:).', ...
                 {'Press "Preview" or "Recognise on filtered photo".'}];
        filt.report.Value = lines;
        log_(lines);
    end

    function onPreviewFilters()
        [F, ok] = runFilters();
        if ~ok, return; end
        S.filtered = F;
        showImage(axRes, F, 'Filtered photo (preview)');
        drawHistograms(S.orig, F);
        log_([{'Preview of the filtered photo (right). "Recognise on filtered photo" searches the plate in it.'}, S.filterNote(:).']);
    end

    function setUseFilters()
        S.useFilters = true;
    end

    function onRecognizeFiltered()
        [F, ok] = runFilters();
        if ~ok || ~ensureModel(), return; end
        sameSize = isequal(size(F, 1:2), size(S.orig, 1:2));
        roi0 = S.roi;
        if ~sameSize && ~isempty(S.roi)                           % Resize changed the picture: the car rectangle is scaled with it
            S.roi = S.roi * (size(F, 2) / size(S.orig, 2));
        end
        S.filtered = F;  S.I = F;
        onRecognize();
        extra = {};
        if ~plate.all.Value && ~isempty(S.lastRes) && ~S.lastRes.found && ~isempty(S.filterNote)
            % nothing found in the filtered photo: say whether the filters are to blame
            opts = {'Format', plate.format.Value, 'Polarity', plate.polarity.Value, 'Consensus', plate.vote.Value};
            if sameSize, opts = [opts, {'ROI', roi0}]; end
            try r0 = recognizePlate(S.orig, S.model, opts{:}); catch, r0 = []; end %#ok<CTCH>
            if ~isempty(r0) && r0.found
                extra = {'', sprintf('The ORIGINAL photo reads %s, so these filters made it worse. Press "Remove filters" or try other filters ("Suggest filters" proposes a chain).', r0.text)};
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
        sameSize = isequal(size(F, 1:2), size(S.orig, 1:2));
        if sameSize, opts = [opts, {'ROI', S.roi}]; end
        try
            r0 = recognizePlate(S.orig, S.model, opts{:});
        catch ME
            fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        fig.Pointer = 'arrow';
        S.filtered = F;  S.I = F;
        if ~sameSize && ~isempty(S.roi), S.roi = S.roi * (size(F, 2) / size(S.orig, 2)); end
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
        S.I = S.orig;  S.filtered = [];  S.filterNote = {};
        setStagesFromChain([]);                                   % the boxes are cleared too, otherwise "Recognise plate" would apply them again
        showImage(axOrig, S.I, 'Original');  cla(axRes);  resetAux();
        filt.report.Value = {'No filter active: the original photo is used.'};
        log_('Filters removed: the original photo is the input again.');
    end

    function setFiltersScripted(chain, pad, kernelText)
        % scripted access: app.setFilters(struct('name', 'Median filter', 'p', 3), 'replicate')
        setStagesFromChain(chain);
        if nargin > 1 && ~isempty(pad), filt.pad.Value = pad; end
        if nargin > 2 && ~isempty(kernelText), filt.kernel.Value = kernelText; end
    end

% ---------------------------- plate recognition ------------------------------
    function ok = ensureModel()
        ok = true;
        if ~isempty(S.model), return; end
        f = fullfile(root, 'models', 'lpr_svm_model_real.mat');      % trained with the real photos
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
        d = uiprogressdlg(fig, 'Title', 'Training SVM', 'Message', ...
            'Rendering characters and training 630 binary SVMs - see the MATLAB command window.', 'Indeterminate', 'on');
        drawnow;
        try
            S.model = trainLPRModel('NPerClass', 200, 'HoldOut', false);
            log_(sprintf('SVM trained: %d support vectors, training-set accuracy %.1f %%', ...
                         size(S.model.svm.SV, 1), 100 * S.model.report.trainAcc));
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
        % every plate the plate SVM accepts (road scenes), car by car if ticked; small plates are marked unreliable
        fig.Pointer = 'watch';
        dlg = [];
        try dlg = uiprogressdlg(fig, 'Title', 'Reading all plates', 'Indeterminate', 'on', ...
                'Message', 'Searching every car of the photo. A big photo with many cars can take a few minutes.'); catch, end %#ok<CTCH>
        drawnow;
        t0 = tic;
        try
            [out, unread, cars] = recognizePlates(S.I, S.model, 'ROI', S.roi, 'Consensus', plate.vote.Value, 'Cars', plate.cars.Value, 'NightVision', plate.night.Value);
        catch ME
            closeDlg(dlg);  fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        closeDlg(dlg);
        fig.Pointer = 'arrow';
        S.lastRes = [];  S.plates = out;  S.unread = unread;  S.cars = cars;
        tabs.SelectedTab = tabPlate;
        ttl = sprintf('%d plate(s) read, %d plate-like region(s) not read', numel(out), numel(unread));
        if ~isempty(cars), ttl = sprintf('%s, %d car(s) (blue)', ttl, numel(cars)); end
        showImage(axOrig, S.I, ttl);
        drawRoi();
        hold(axOrig, 'on');
        for k = 1:numel(cars)
            rectangle(axOrig, 'Position', cars(k).box, 'EdgeColor', [0.2 0.7 1], 'LineWidth', 1, 'LineStyle', ':');
        end
        lines = cell(1, numel(out));
        for k = 1:numel(out)
            if out(k).reliable, col = [1 0.1 0.1]; else, col = [1 0.6 0]; end
            rectangle(axOrig, 'Position', out(k).box, 'EdgeColor', col, 'LineWidth', 2);
            text(axOrig, out(k).box(1), max(out(k).box(2) - 3, 1), sprintf('%d: %s', k, out(k).text), 'Color', [1 1 0], 'VerticalAlignment', 'bottom', ...
                 'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', [0 0 0], 'Interpreter', 'none', 'Clipping', 'on');
            note = '';
            if ~out(k).reliable, note = '  (plate too small: reading unreliable)'; end
            if out(k).lines == 2, note = [note '  (two-line plate: upper and lower row)']; end %#ok<AGROW>
            lines{k} = sprintf('%d) %s   plate %d px wide, plate-SVM score %.2f%s', k, out(k).text, out(k).width, out(k).score, note);
        end
        for k = 1:numel(unread)                                    % plate-like regions that could not be read
            rectangle(axOrig, 'Position', unread(k).box, 'EdgeColor', [0.75 0.75 0.75], 'LineWidth', 1.5, 'LineStyle', '--');
            text(axOrig, unread(k).box(1), max(unread(k).box(2) - 3, 1), sprintf('?%d', k), 'Color', [0.85 0.85 0.85], 'FontSize', 9, 'VerticalAlignment', 'bottom', ...
                 'Interpreter', 'none', 'Clipping', 'on');
            lines{end+1} = sprintf('?%d) plate-like region, %d px wide, not read (too small, blurred, or glare)', k, unread(k).width); %#ok<AGROW>
        end
        hold(axOrig, 'off');
        items = arrayfun(@(k) sprintf('%d: %s', k, out(k).text), 1:numel(out), 'UniformOutput', false);
        if isempty(items), plate.pick.Items = {'-'};  plate.pick.ItemsData = {0};  plate.pick.Value = 0;
        else, plate.pick.Items = items;  plate.pick.ItemsData = num2cell(1:numel(out));  plate.pick.Value = 1; end
        showPlateDetail(1);
        showGallery(out, unread, cars);
        if isempty(out)
            plate.result.Text = '0 plates';  plate.result.FontSize = 26;
            msg = sprintf(['No plate could be read [%.1f s]. A plate needs about 100 pixels of width to be read; plates of 30 pixels or less ' ...
                           'cannot be found or read by any filter. For a dark photo tick "Night vision".'], toc(t0));
            if ~isempty(unread)
                msg = sprintf('%s %d plate-like region(s) were found (grey dashed boxes): look at them in the photo or take a closer picture.', msg, numel(unread));
            end
            log_([{msg}, lines]);
        else
            plate.result.Text = strjoin({out.text}, '   ');  plate.result.FontSize = 26 - 8 * (numel(out) > 1) - 4 * (numel(out) > 3);
            log_([{sprintf('%d plate(s) read, %d plate-like region(s) not read [%.1f s]. The readings of small (orange) plates are often wrong.', numel(out), numel(unread), toc(t0))}, lines]);
        end
        if ~isempty(S.truth), infoBox.Value = [infoBox.Value(:); {['Ground truth (the photo of the list): ' S.truth]}]; end
    end

    function closeDlg(d)
        if ~isempty(d), try close(d); catch, end, end %#ok<CTCH>
    end

    function onPickPlate()
        showPlateDetail(plate.pick.Value);
    end

    function showPlateDetail(k)
        % "Result": the plate k of the last "Find ALL plates" cut out and segmented, the number above it
        out = S.plates;
        if isempty(out) || k < 1 || k > numel(out)
            cla(axRes);  title(axRes, 'Result');  return
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

    function showGallery(out, unread, cars)
        % one tile per plate: its number above, the car (when it was cut out) or the plate in the middle, the characters the SVM saw below
        % (red frame = readable size, orange = small and unreliable, grey = plate-like region that was not read)
        resetAux();
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
            reg = round(b);
            if k <= nO && ~isempty(cars)
                q = find([cars.plate] == k, 1);
                if ~isempty(q), reg = round(cars(q).box); end
            end
            x0r = max(1, reg(1));  y0r = max(1, reg(2));  x1r = min(size(I, 2), reg(1) + reg(3) - 1);  y1r = min(size(I, 1), reg(2) + reg(4) - 1);
            crop = I(y0r:y1r, x0r:x1r, :);
            if k > nO, col = [0.6 0.6 0.6]; elseif out(k).reliable, col = [1 0.1 0.1]; else, col = [1 0.6 0]; end
            crop = frameBox(crop, [b(1) - x0r + 1, b(2) - y0r + 1, b(3), b(4)], col);       % the plate inside the picture
            sc = min((ph - 4) / size(crop, 1), (pw - 4) / size(crop, 2));
            crop = imResize(crop, sc, 'bilinear');
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
        showImage(axAux, canvas, 'All plates: the number is above every picture, the characters the SVM saw below it (red = readable, orange = small, grey = not read)');
        hold(axAux, 'on');
        for k = 1:nAll
            text(axAux, xs(k) + 3, ys(k), labels{k}, 'Color', [1 1 0], 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none', 'VerticalAlignment', 'middle');
        end
        hold(axAux, 'off');
    end

    function C = frameBox(C, bx, col)
        % draw a 1 pixel frame [x y w h] into the picture C (the plate inside its car)
        x0 = max(1, round(bx(1)));  y0 = max(1, round(bx(2)));
        x1 = min(size(C, 2), round(bx(1) + bx(3)));  y1 = min(size(C, 1), round(bx(2) + bx(4)));
        if x1 <= x0 || y1 <= y0, return; end
        for ch = 1:3
            C(y0, x0:x1, ch) = col(ch);  C(y1, x0:x1, ch) = col(ch);  C(y0:y1, x0, ch) = col(ch);  C(y0:y1, x1, ch) = col(ch);
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
            res = recognizePlate(S.I, S.model, 'Format', plate.format.Value, 'Polarity', plate.polarity.Value, 'ROI', S.roi, 'Consensus', plate.vote.Value);
        catch ME
            fig.Pointer = 'arrow';  uialert(fig, ME.message, 'Recognition failed');  return;
        end
        fig.Pointer = 'arrow';
        S.lastRes = res;
        tabs.SelectedTab = tabPlate;
        showImage(axOrig, S.I, 'Input and detected plate');
        drawRoi();
        S.plates = [];  plate.pick.Items = {'-'};  plate.pick.ItemsData = {0};  plate.pick.Value = 0;
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
                               'for this system, so the reading is probably wrong. Use a closer photo or crop around one car.'], msg, round(res.bbox(3)));
            end
            if res.rectified
                msg = sprintf('%s\n(The plate was seen at an angle: it was straightened first, perspective correction by a homography.)', msg);
            end
            if ~isempty(S.truth), msg = sprintf('%s\nGround truth: %s', msg, S.truth); end
            log_(msg);
            S.result = repmat(s.plate, [1 1 3]);
        else
            cla(axRes);  resetAux();  axis(axAux, 'off');
            plate.result.Text = '?';
            if ~isempty(res.guess) && startsWith(res.reason, 'plate too small')
                rectangle(axOrig, 'Position', res.guess, 'EdgeColor', [1 0.6 0], 'LineWidth', 2, 'LineStyle', '--');
                log_(sprintf(['Plate located but too small to read: %d px wide (dashed orange box), at least %d px are needed. ' ...
                              'Use a closer photo, or pick the vehicle with "Pick vehicle..." from a larger photo.'], round(res.guess(3)), 40));
            else
                msg = 'No plate found.';
                if ~isempty(res.reason), msg = sprintf('No plate found (%s).', res.reason); end
                log_([msg ' This system needs a plate that is at least ~100 pixels wide with 4 or more separable characters. ' ...
                      'Try a closer photo, pick one vehicle (car, bus, truck, motorcycle) with "Pick vehicle...", or set the character colour. ' ...
                      'For a dark photo tick "Night vision"; for a small or far plate tick "Car by car" with "Find ALL plates".']);
            end
        end
    end

    function onPickCar()
        % ginput does not work in a uifigure, so the photo is shown in an ordinary figure window
        if isempty(S.I), uialert(fig, 'Open an image first.', 'No image'); return; end
        roi = pickCarROI(S.I);
        if isempty(roi)
            log_('No car marked: the whole photo is searched.');
            return
        end
        S.roi = roi;
        plate.carLabel.Text = sprintf('Vehicle: x %d, y %d, %d x %d px', roi(1), roi(2), roi(3), roi(4));
        showImage(axOrig, S.I, 'Input (chosen car in yellow)');
        drawRoi();
        log_('Vehicle chosen. Press "Recognise plate": only this part of the photo is searched.');
    end

    function onClearCar()
        S.roi = [];
        plate.carLabel.Text = 'Vehicle: whole photo';
        if ~isempty(S.I), showImage(axOrig, S.I, 'Input'); end
        log_('The whole photo is searched.');
    end

    function drawRoi()
        if ~isempty(S.roi)
            rectangle(axOrig, 'Position', S.roi, 'EdgeColor', [1 0.9 0], 'LineWidth', 1.5, 'LineStyle', '--');
        end
    end

    function onPipeline()
        if isempty(S.lastRes), onRecognize(); end
        if isempty(S.lastRes), return; end
        showPipeline(S.I, S.lastRes);
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
