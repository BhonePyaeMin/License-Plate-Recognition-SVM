function res = demo_lpr(imageFile, format, pick)
%DEMO_LPR  Recognise the license plate in an image and show every pipeline stage.
%   >> demo_lpr                         % synthetic car photo (random plate)
%   >> demo_lpr('images/car1.jpg')      % your own photo
%   >> demo_lpr('images/car1.jpg', 'LLL DDDD')   % + known layout (L letter, D digit)
%   >> demo_lpr('images/car1.jpg', '', 'pick')   % you click two corners around ONE car first;
%                                                % only that part of the photo is searched
%   The model models/lpr_svm_model_real.mat (trained with the real photos, see
%   train_real_model) is used when it exists, otherwise models/lpr_svm_model.mat, which
%   is created on first use (about 1 minute).
%   The figure is also saved to results/demo_lpr.png.

root = fileparts(mfilename('fullpath'));
setup_toolbox;
if nargin < 2, format = ''; end
if nargin < 3, pick = ''; end

modelFile = fullfile(root, 'models', 'lpr_svm_model_real.mat');    % learned from synthetic + real photos
if ~exist(modelFile, 'file'), modelFile = fullfile(root, 'models', 'lpr_svm_model.mat'); end
if ~exist(modelFile, 'file')
    disp('No trained model found - training one now ...');
    train_lpr_model;
end
S = load(modelFile);  model = S.model;

truth = '';
if nargin < 1 || isempty(imageFile)
    tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
    [img, gt] = makeScene(tpl, find(tpl.isTest), 'Hard', 0.4);
    truth = gt.text;
    fprintf('Synthetic scene generated (true plate: %s)\n', truth);
else
    img = imread(imageFile);
end

roi = [];
if strcmpi(pick, 'pick')                                   % one car chosen by two clicks
    roi = pickCarROI(img);
    if isempty(roi), disp('No car marked - the whole photo is searched.'); end
end

tic;
res = recognizePlate(img, model, 'Format', format, 'ROI', roi);
t = toc;
if res.found
    fprintf('Plate read: %s   (%.2f s)\n', res.text, t);
    if ~isempty(truth), fprintf('Ground truth: %s  ->  %s\n', truth, ternary(strcmp(truth, res.text), 'CORRECT', 'different')); end
else
    fprintf('No plate found');
    if ~isempty(res.reason), fprintf(' (%s)', res.reason); end
    fprintf('.\n');
end

fig = showPipeline(img, res);
if ~exist(fullfile(root, 'results'), 'dir'), mkdir(fullfile(root, 'results')); end
saveas(fig, fullfile(root, 'results', 'demo_lpr.png'));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
