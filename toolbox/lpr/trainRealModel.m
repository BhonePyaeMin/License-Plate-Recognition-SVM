function model = trainRealModel(varargin)
%TRAINREALMODEL  Train the character SVM on synthetic characters plus real ones.
%   model = TRAINREALMODEL('Name', value, ...)
%   The synthetic characters (all fonts, as in TRAINLPRMODEL) are combined with
%   characters cut from the real photos by COLLECTREALCHARS. Every real character is
%   used several times with small random distortions, because there are far fewer of
%   them than synthetic ones.
%   Options: 'Subset'     real photos to learn from: 'dev' (default, evaluate on the
%                         'test' photos afterwards), 'all' (final model) or 'none'
%            'Replicate'  distorted copies of every real character (default 12)
%            'NPerClass'  synthetic characters per class (default 250)
%            'C'          SVM box constraint (default 10)
%            'SaveTo'     .mat file (default models/lpr_svm_model_real.mat; '' = none)
%            'Seed'       random seed (default 7)
%            'Signed'     true (default): signed-orientation HOG (18 bins, 648 values, see HOGFEATURES); the model
%                         then carries model.hog.signed = true and RECOGNIZEPLATE uses the same features
%   model.svm, model.charset as in TRAINLPRMODEL; model.report lists the data used.

p = inputParser;
p.addParameter('Subset', 'dev');
p.addParameter('Group', 'project');
p.addParameter('Replicate', 12);
p.addParameter('NPerClass', 250);
p.addParameter('C', 10);
p.addParameter('SaveTo', 'default');
p.addParameter('Seed', 7);
p.addParameter('Signed', true);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if strcmp(o.SaveTo, 'default'), o.SaveTo = fullfile(root, 'models', 'lpr_svm_model_real.mat'); end
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));

fprintf('Synthetic characters: %d per class ...\n', o.NPerClass);
[Xs, ys] = generateCharDataset(tpl, 1:size(tpl.variants, 1), o.NPerClass, o.Seed, o.Signed);
nBins = 9;  if o.Signed, nBins = 18; end

Xr = zeros(0, size(Xs, 2));  yr = zeros(0, 1);  nReal = 0;
if ~strcmpi(o.Subset, 'none')
    fprintf('Real characters (%s photos) ...\n', o.Subset);
    S = collectRealChars('Subset', o.Subset, 'Group', o.Group);
    nReal = numel(S.y);
    rng(o.Seed + 1);
    for k = 1:nReal
        for r = 1:o.Replicate
            N = jitterChar(S.imgs(:, :, k), r == 1);
            Xr(end+1, :) = hogFeatures(N, 8, nBins, o.Signed);  yr(end+1, 1) = S.y(k); %#ok<AGROW>
        end
    end
end

X = [Xs; Xr];  y = [ys; yr];
fprintf('Training one-vs-one RBF SVM on %d synthetic + %d real-derived samples ...\n', size(Xs, 1), size(Xr, 1));
t0 = tic;
svm = svmTrain(X, y, 'C', o.C);
model.svm = svm;
model.charset = tpl.chars;
model.hog = struct('cellSize', 8, 'nBins', nBins, 'signed', o.Signed);
model.report = struct('trainSeconds', toc(t0), 'nSynthetic', size(Xs, 1), 'nRealChars', nReal, ...
                      'nRealSamples', size(Xr, 1), 'subset', o.Subset, 'replicate', o.Replicate);
fprintf('  trained in %.1f s, %d shared support vectors\n', model.report.trainSeconds, size(svm.SV, 1));
if ~isempty(o.SaveTo), save(o.SaveTo, 'model'); fprintf('Model saved to %s\n', o.SaveTo); end
end

function N = jitterChar(N, keepOriginal)
% small random distortion of a normalised 32 x 32 character (first copy is unchanged)
if keepOriginal, return; end
N = geometricTransforms(N, 'rotate', (rand - 0.5) * 12, 'bilinear');
N = geometricTransforms(N, 'shear', (rand - 0.5) * 0.2, 0, 'bilinear');
N = geometricTransforms(N, 'scale', 0.9 + 0.2 * rand, 0.9 + 0.2 * rand, 'bilinear');
N = geometricTransforms(N, 'translate', (rand - 0.5) * 3, (rand - 0.5) * 3, 'bilinear');
N = normalizeChar(N > 0.45, 32);
end
