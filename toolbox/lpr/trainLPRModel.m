function model = trainLPRModel(varargin)
%TRAINLPRMODEL  Train the character-recognition SVM and save it.
%   model = TRAINLPRMODEL('Name', value, ...)
%   Options: 'NPerClass'   training images per character (default 120)
%            'C'           SVM box constraint (default 10)
%            'Gamma'       RBF width ('scale' default)
%            'HoldOut'     true (default): train on the fonts with tpl.isTest == false
%                          and report accuracy on the unseen fonts. false: train on
%                          every font (use this for the final model).
%            'SaveTo'      .mat file for the model (default models/lpr_svm_model.mat)
%            'Seed'        random seed (default 7)
%   model.svm     trained multi-class SVM        model.charset  class -> character
%   model.report  accuracy on seen / unseen fonts and training time

p = inputParser;
p.addParameter('NPerClass', 120);
p.addParameter('C', 10);
p.addParameter('Gamma', 'scale');
p.addParameter('HoldOut', true);
p.addParameter('SaveTo', '');
p.addParameter('Seed', 7);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if isempty(o.SaveTo), o.SaveTo = fullfile(root, 'models', 'lpr_svm_model.mat'); end
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
trainFonts = find(~tpl.isTest);
testFonts  = find(tpl.isTest);
if ~o.HoldOut, trainFonts = 1:size(tpl.variants, 1); end

fprintf('Generating %d x 36 training characters from %d fonts ...\n', o.NPerClass, numel(trainFonts));
t0 = tic;
[Xtr, ytr] = generateCharDataset(tpl, trainFonts, o.NPerClass, o.Seed);
fprintf('  done in %.1fs (%d features)\n', toc(t0), size(Xtr, 2));

fprintf('Training one-vs-one RBF SVM (C = %g) ...\n', o.C);
t0 = tic;
svm = svmTrain(Xtr, ytr, 'C', o.C, 'Gamma', o.Gamma, 'Verbose', true);
trainTime = toc(t0);
fprintf('  trained in %.1fs, %d shared support vectors\n', trainTime, size(svm.SV, 1));

model.svm = svm;
model.charset = tpl.chars;
model.report.trainTime = trainTime;
model.report.nTrain = size(Xtr, 1);

pTrain = svmPredict(svm, Xtr);
model.report.trainAcc = mean(pTrain == ytr);
fprintf('  accuracy on training samples: %.2f%%\n', 100 * model.report.trainAcc);

[Xse, yse] = generateCharDataset(tpl, trainFonts, 20, o.Seed + 100);
model.report.seenFontAcc = mean(svmPredict(svm, Xse) == yse);
fprintf('  accuracy on NEW samples of seen fonts: %.2f%%\n', 100 * model.report.seenFontAcc);
if o.HoldOut
    [Xte, yte] = generateCharDataset(tpl, testFonts, 30, o.Seed + 200);
    model.report.unseenFontAcc = mean(svmPredict(svm, Xte) == yte);
    fprintf('  accuracy on UNSEEN fonts (%d held out): %.2f%%\n', numel(testFonts), 100 * model.report.unseenFontAcc);
end

if ~isempty(o.SaveTo)
    save(o.SaveTo, 'model');
    fprintf('Model saved to %s\n', o.SaveTo);
end
end
