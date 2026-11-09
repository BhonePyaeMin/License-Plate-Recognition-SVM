%TRAIN_LPR_MODEL  Build the character SVM used by the license plate recognizer.
%   >> train_lpr_model
%
%   Two models are trained on synthetic characters rendered from the fonts
%   installed on this computer (see toolbox/lpr/buildGlyphTemplates.m):
%     models/lpr_svm_model_holdout.mat - trained WITHOUT 4 fonts, used to measure
%                                        how well the SVM generalises to new fonts
%     models/lpr_svm_model.mat         - trained on ALL fonts, used by the GUI/demo
%   Takes roughly one minute. Run it again after installing new fonts or after
%   deleting models/glyph_templates.mat.

setup_toolbox;
nPerClass = 250;

fprintf('\n=== 1/2  hold-out model (for evaluation) ===\n');
holdout = trainLPRModel('NPerClass', nPerClass, 'HoldOut', true, ...
    'SaveTo', fullfile('models', 'lpr_svm_model_holdout.mat'));

fprintf('\n=== 2/2  final model (all fonts) ===\n');
model = trainLPRModel('NPerClass', nPerClass, 'HoldOut', false, ...
    'SaveTo', fullfile('models', 'lpr_svm_model.mat'));

fprintf('\nDone. Hold-out character accuracy on unseen fonts: %.2f %%\n', ...
    100 * holdout.report.unseenFontAcc);
