function train_char_valid(stage)
%TRAIN_CHAR_VALID  Train the character-validity SVM and put it into the model files (about 12 minutes each).
%   >> train_char_valid          both models
%   >> train_char_valid('dev')   only models/lpr_svm_model_real_dev.mat (learns from the dev photos only)
%   >> train_char_valid('all')   only models/lpr_svm_model_real.mat (learns from all photos; used by the GUI)
%   The recogniser then refuses plates whose "characters" are streaks or blobs (a van body, a wall, a grille).
%   See TRAINCHARVALIDMODEL and CHARSLOOKVALID.
setup_toolbox;
if nargin < 1, stage = 'both'; end
for q = {'dev', 'all'}
    sub = q{1};
    if ~any(strcmpi(stage, {'both', sub})), continue; end
    if strcmp(sub, 'dev'), mf = 'lpr_svm_model_real_dev.mat'; else, mf = 'lpr_svm_model_real.mat'; end
    cv = trainCharValidModel('Subset', sub, 'SaveTo', fullfile('models', ['char_valid_' sub '.mat']));
    M = load(fullfile('models', mf));  model = M.model;  model.charValid = cv;
    save(fullfile('models', mf), 'model');
    fprintf('put the character-validity SVM into %s\n', mf);
end
end
