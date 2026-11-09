function R = evaluateReal(model, varargin)
%EVALUATEREAL  Measure the recogniser on the real car photos in images/real.
%   R = EVALUATEREAL(model, 'Name', value, ...)
%   Options: 'Subset'     'all' (default) | 'dev' | 'test' - images/real/labels.csv has a
%                         split column; 'dev' photos are used for tuning and for
%                         collecting real training characters, 'test' photos are kept
%                         aside for the final numbers
%            'Folder'     folder with the photos and labels.csv (default images/real)
%            'RecOptions' cell array of extra RECOGNIZEPLATE options
%            'Transform'  function handle applied to every photo before recognition, e.g.
%                         @(I, k) simulateNight(I, 'lit', k) (k = photo number, for a repeatable result)
%            'Figure'     PNG file for an overlay of all results ('' = none)
%            'Verbose'    print one line per photo (default false)
%   labels.csv columns: file, plate_text (letters and digits only), split, note.
%   The 'note' column marks night photos (note = night); day and night photos are also reported
%   separately (fields R.isNight, R.day, R.night).
%   Measures (per photo and averaged)
%     read      a plate was found and characters were produced
%     exact     the plate text is exactly right
%     charAcc   1 - edit distance / true length, averaged
%   Whether the box really lies on the plate is not measured automatically; the
%   overlay figure is meant for checking that by eye.

p = inputParser;
p.addParameter('Subset', 'all');
p.addParameter('Group', 'project');
p.addParameter('Folder', '');
p.addParameter('RecOptions', {});
p.addParameter('Transform', []);
p.addParameter('Figure', '');
p.addParameter('Verbose', false);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if isempty(o.Folder), o.Folder = fullfile(root, 'images', 'real'); end
T = readtable(fullfile(o.Folder, 'labels.csv'), 'TextType', 'string', 'Delimiter', ',');
T = T(selectRealPhotos(T, o.Subset, o.Group), :);
n = height(T);

R.file = T.file;  R.truth = T.plate_text;
R.text = strings(n, 1);  R.read = false(n, 1);  R.exact = false(n, 1);
R.charAcc = zeros(n, 1);  R.seconds = zeros(n, 1);  R.bbox = zeros(n, 4);
imgs = cell(n, 1);
for k = 1:n
    img = imread(fullfile(o.Folder, T.file(k)));
    if ~isempty(o.Transform), img = o.Transform(img, k); end
    t0 = tic;
    res = recognizePlate(img, model, o.RecOptions{:});
    R.seconds(k) = toc(t0);
    R.read(k) = res.found;
    R.text(k) = string(res.text);
    truth = char(T.plate_text(k));
    R.exact(k) = strcmp(res.text, truth);
    R.charAcc(k) = max(0, 1 - editDistance(res.text, truth) / numel(truth));
    if ~isempty(res.bbox), R.bbox(k, :) = res.bbox; end
    if ~isempty(o.Figure), imgs{k} = img; end
    if o.Verbose
        fprintf('%-11s truth %-9s read %-10s %s\n', T.file(k), T.plate_text(k), R.text(k), ternary(R.exact(k), 'OK', ''));
    end
end
R.n = n;
R.readRate = mean(R.read);
R.exactRate = mean(R.exact);
R.charAccuracy = mean(R.charAcc);
R.secondsPerImage = mean(R.seconds);
fprintf('%s photos (%d): text produced %d, exact %d (%.1f %%), character accuracy %.1f %%, %.2f s/photo\n', ...
    o.Subset, n, sum(R.read), sum(R.exact), 100 * R.exactRate, 100 * R.charAccuracy, R.secondsPerImage);

isNight = false(n, 1);
tag = '';  if ~isempty(o.Transform), tag = ', photos transformed'; end
if ismember('note', T.Properties.VariableNames), isNight = strcmpi(string(T.note), "night"); end
R.isNight = isNight;
for grp = ["day", "night"]
    m = isNight == (grp == "night");
    R.(char(grp)) = struct('n', nnz(m), 'exact', sum(R.exact(m)), 'charAccuracy', mean(R.charAcc(m)), 'read', sum(R.read(m)));
    if ~any(m)
        fprintf('  %-5s: no photos (mark night photos with note = night in labels.csv)\n', grp);
    else
        fprintf('  %-5s (%2d photos%s): exact %d (%.1f %%), character accuracy %.1f %%, text produced %d\n', grp, nnz(m), tag, ...
            sum(R.exact(m)), 100 * mean(R.exact(m)), 100 * R.(char(grp)).charAccuracy, sum(R.read(m)));
    end
end

if ~isempty(o.Figure)
    cols = 5;  rows = ceil(n / cols);
    f = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 1700 rows * 270]);
    for k = 1:n
        ax = subplot(rows, cols, k);
        showImage(ax, imgs{k});
        if all(R.bbox(k, :) > 0), rectangle(ax, 'Position', R.bbox(k, :), 'EdgeColor', 'r', 'LineWidth', 2); end
        if R.exact(k), col = [0 0.55 0]; else, col = [0.8 0 0]; end
        title(ax, sprintf('%s | %s', R.truth(k), R.text(k)), 'Color', col, 'FontSize', 8, 'Interpreter', 'none');
    end
    exportgraphics(f, o.Figure, 'Resolution', 80);
    close(f);
end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
