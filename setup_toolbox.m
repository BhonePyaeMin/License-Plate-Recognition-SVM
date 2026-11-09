function setup_toolbox()
%SETUP_TOOLBOX  Add every toolbox folder to the MATLAB path (run once per session).
%   >> setup_toolbox

root = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(root, 'toolbox')));
addpath(root);
fprintf('License Plate Recognition toolbox added to the path:\n  %s\n', root);
end
