function train_real_model(stage)
%TRAIN_REAL_MODEL  Train the SVMs that learn from the real car photos in images/real.
%   >> train_real_model        (about 25 minutes)
%   >> train_real_model('plate')   only retrain the two plate SVMs and put them into the
%                                  existing model files (about 3 minutes)
%   >> train_real_model('oa_dev')  all SVMs learn from the project photos AND the 444 OpenALPR photos (dev part) -> models/lpr_svm_model_oa_dev.mat
%   >> train_real_model('oa_all')  the same with all photos -> models/lpr_svm_model_oa.mat (about 1-2 hours each)
%   >> train_real_model('oa_chars')  only the character SVMs, learning from the project AND the OpenALPR photos, put into the existing model files
%                                  (the plate SVM and the validity SVM stay: this combination was the best compromise, see the README, round 10)
%   >> train_real_model('chars')   only retrain the character SVMs (signed HOG features) and put them into
%                                  the existing model files, which keep their plate SVM and character-validity SVM
%
%   labels.csv marks every photo as 'dev' or 'test'. Two sets of models are trained:
%     1. DEV models (learn from the 'dev' photos only) -> models/lpr_svm_model_real_dev.mat
%        They are evaluated on the 'test' photos, which they have never seen: this is
%        the honest estimate of accuracy on new real photos, printed at the end.
%     2. FINAL models (learn from all photos) -> models/lpr_svm_model_real.mat
%        used by the GUI and demo_lpr. No held-out photos remain for them, so quote the
%        numbers of step 1 for performance, not numbers measured with these models.
%   Each set has a character SVM (synthetic + real characters) and a plate / not-plate
%   SVM (stored in model.plate) that ranks the candidate regions of a photo and scores the
%   sliding windows. The plate SVM learns the true plate positions of images/real/plate_boxes.csv
%   (labels 'location') and is trained again after hard-negative mining ('Mine').

setup_toolbox;
if nargin < 1, stage = 'all'; end
base = load(fullfile('models', 'lpr_svm_model.mat'));              % synthetic-only character SVM

if strcmpi(stage, 'plate')          % quick mode: only the two plate SVMs, put into the existing models
    for q = {'dev', 'all'}
        sub = q{1};
        if strcmp(sub, 'dev'), mf = 'lpr_svm_model_real_dev.mat'; pf = 'plate_svm_dev.mat';
        else, mf = 'lpr_svm_model_real.mat'; pf = 'plate_svm.mat'; end
        pm = trainPlateModel(base.model, 'Subset', sub, 'Labels', 'location', 'Mine', true, 'SaveTo', fullfile('models', pf));
        M = load(fullfile('models', mf));  model = M.model;  model.plate = pm;
        save(fullfile('models', mf), 'model');
        fprintf('updated %s\n', mf);
    end
    return
end

if any(strcmpi(stage, {'oa_dev', 'oa_all'}))   % all SVMs learn from the project photos AND the 444 OpenALPR photos (images/real/openalpr)
    sub = 'dev';  mf = 'lpr_svm_model_oa_dev.mat';
    if strcmpi(stage, 'oa_all'), sub = 'all';  mf = 'lpr_svm_model_oa.mat'; end
    tag = sub;  if strcmp(sub, 'all'), tag = 'all'; end
    fprintf('\n=== OpenALPR + project photos, subset %s ===\n', sub);
    pm = trainPlateModel(base.model, 'Subset', sub, 'Group', 'all', 'Labels', 'location', 'Mine', true, 'Refresh', true, 'TopK', 8, 'Jitter', 4, ...
                         'MineNeg', 8, 'MinePos', 4, 'SaveTo', fullfile('models', ['plate_svm_oa_' tag '.mat']));
    model = trainRealModel('Subset', sub, 'Group', 'all', 'Replicate', 8, 'SaveTo', '');
    cv = trainCharValidModel('Subset', sub, 'Group', 'all', 'TopK', 8, 'Replicate', 1, 'NNeg', 2500, 'SaveTo', fullfile('models', ['char_valid_oa_' tag '.mat']));
    model.plate = pm;  model.charValid = cv;
    save(fullfile('models', mf), 'model');
    fprintf('saved %s\n', mf);
    return
end

if any(strcmpi(stage, {'chars', 'oa_chars'}))          % quick mode: only the character SVMs, put into the existing models
    for q = {'dev', 'all'}
        sub = q{1};
        if strcmp(sub, 'dev'), mf = 'lpr_svm_model_real_dev.mat'; else, mf = 'lpr_svm_model_real.mat'; end
        M = load(fullfile('models', mf));  model = M.model;
        if strcmpi(stage, 'oa_chars'), m2 = trainRealModel('Subset', sub, 'Group', 'all', 'Replicate', 8, 'SaveTo', '');   % project + OpenALPR photos
        else, m2 = trainRealModel('Subset', sub, 'SaveTo', ''); end
        model.svm = m2.svm;  model.charset = m2.charset;  model.hog = m2.hog;  model.report = m2.report;
        save(fullfile('models', mf), 'model');
        fprintf('updated %s\n', mf);
        if strcmp(sub, 'dev'), evaluateReal(model, 'Subset', 'test', 'Verbose', true); end
    end
    return
end

fprintf('\n=== 1/2  DEV models (dev photos only) ===\n');
pmDev = trainPlateModel(base.model, 'Subset', 'dev', 'Labels', 'location', 'Mine', true, 'Refresh', true, 'SaveTo', fullfile('models', 'plate_svm_dev.mat'));
model = trainRealModel('Subset', 'dev', 'SaveTo', '');
model.plate = pmDev;
save(fullfile('models', 'lpr_svm_model_real_dev.mat'), 'model');
fprintf('\nHeld-out evaluation of the DEV models on the test photos:\n');
evaluateReal(model, 'Subset', 'test', 'Verbose', true);

fprintf('\n=== 2/2  FINAL models (all photos) ===\n');
pmAll = trainPlateModel(base.model, 'Subset', 'all', 'Labels', 'location', 'Mine', true, 'Refresh', true, 'SaveTo', fullfile('models', 'plate_svm.mat'));
model = trainRealModel('Subset', 'all', 'SaveTo', '');
model.plate = pmAll;
save(fullfile('models', 'lpr_svm_model_real.mat'), 'model');
fprintf('\nDone. Final model saved to models/lpr_svm_model_real.mat\n');
end
