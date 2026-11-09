function markPlateBoxes
%MARKPLATEBOXES  Add your own photos to images/real: click the plate, type its text.
%   >> markPlateBoxes
%   For every .jpg / .jpeg / .png in images/real that has no row in images/real/plate_boxes.csv
%   (or none in labels.csv) the photo is shown in a window:
%     1. click the TOP-LEFT and then the BOTTOM-RIGHT corner of the plate (press Enter instead of
%        clicking to skip the photo, close the window to stop);
%     2. type the plate text in the command window (letters and digits only; spaces and hyphens
%        are removed; empty = skip the photo);
%     3. press Enter to accept the proposed split, or type dev / test, and the note.
%   Two lines are then appended together, one to each file:
%        plate_boxes.csv   file,x,y,w,h,manual
%        labels.csv        file,plate_text,split,note        (note defaults to "night")
%   Every third new photo is proposed as 'test', the others as 'dev'. Do NOT use the 'test'
%   photos when you choose any setting or threshold: they are only for the final numbers.
%   After every append the two files are checked: they must list exactly the same photos with
%   positive box sizes (run_tests checks this too); if not, the two new lines are removed again.
%   Afterwards run train_real_model (about 25 minutes): the character SVM and the plate SVM learn
%   from the new photos, and evaluateReal reports day and night separately.

root = fileparts(mfilename('fullpath'));
setup_toolbox;
folder = fullfile(root, 'images', 'real');
boxFile = fullfile(folder, 'plate_boxes.csv');
labFile = fullfile(folder, 'labels.csv');
if ~exist(boxFile, 'file'), error('markPlateBoxes:files', 'plate_boxes.csv not found in %s', folder); end
if ~exist(labFile, 'file'), error('markPlateBoxes:files', 'labels.csv not found in %s', folder); end

D = [dir(fullfile(folder, '*.jpg')); dir(fullfile(folder, '*.jpeg')); dir(fullfile(folder, '*.png'))];
names = sort(string({D.name}));
B = readtable(boxFile, 'TextType', 'string', 'Delimiter', ',');
L = readtable(labFile, 'TextType', 'string', 'Delimiter', ',');
todo = names(~ismember(names, B.file) | ~ismember(names, L.file));
if isempty(todo)
    fprintf('Every photo in images/real already has a plate box and a label. Nothing to do.\n');
    return
end
fprintf('%d new photo(s) to mark. Click the plate corners (Enter = skip, close window = stop).\n', numel(todo));
nNew = sum(strcmpi(L.note, "night"));                       % for the 1-in-3 test split

for k = 1:numel(todo)
    f = todo(k);
    img = imread(fullfile(folder, f));
    if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
    fig = figure('Name', char(f), 'NumberTitle', 'off', 'Color', 'w', 'Units', 'normalized', 'Position', [0.1 0.08 0.8 0.84]);
    ax = axes('Parent', fig);
    showImage(ax, img, sprintf('%s   (%d/%d): click TOP-LEFT then BOTTOM-RIGHT corner of the plate', f, k, numel(todo)));
    try
        [x, y] = ginput(2);
    catch                                                   % window closed: stop
        fprintf('Stopped.\n');  return
    end
    if numel(x) < 2
        if isvalid(fig), close(fig); end
        fprintf('%s skipped.\n', f);  continue
    end
    [H, W, ~] = size(img);
    x = min(max(round(x), 1), W);  y = min(max(round(y), 1), H);
    box = [min(x), min(y), abs(x(2) - x(1)) + 1, abs(y(2) - y(1)) + 1];
    rectangle(ax, 'Position', box, 'EdgeColor', 'r', 'LineWidth', 1.5);  drawnow;
    if any(box(3:4) < 8)
        fprintf('%s: box too small (%d x %d), photo skipped.\n', f, box(3), box(4));
        if isvalid(fig), close(fig); end
        continue
    end

    txt = '';
    while true
        txt = upper(regexprep(strtrim(input(sprintf('Plate text of %s (letters and digits, Enter = skip): ', f), 's')), '[\s\-]', ''));
        if isempty(txt) || ~isempty(regexp(txt, '^[0-9A-Z]{3,9}$', 'once')), break; end
        fprintf('  Only the letters A-Z and digits 0-9, 3 to 9 characters.\n');
    end
    if isvalid(fig), close(fig); end
    if isempty(txt), fprintf('%s skipped.\n', f);  continue; end

    split = 'dev';  if mod(nNew + 1, 3) == 0, split = 'test'; end
    s = strtrim(input(sprintf('  split [%s] (dev/test, Enter = accept): ', split), 's'));
    if ismember(lower(s), {'dev', 'test'}), split = lower(s); end
    note = 'night';
    s = strtrim(input('  note [night] (Enter = accept, or type e.g. day): ', 's'));
    if ~isempty(s), note = regexprep(s, '[,\s]', '_'); end

    % append both lines, then check; undo both if the files disagree
    hadBox = ismember(f, B.file);  hadLab = ismember(f, L.file);
    if ~hadBox, appendLine(boxFile, sprintf('%s,%d,%d,%d,%d,manual', f, box)); end
    if ~hadLab, appendLine(labFile, sprintf('%s,%s,%s,%s', f, txt, split, note)); end
    [ok, msg] = checkFiles(boxFile, labFile);
    if ~ok
        if ~hadBox, dropLastLine(boxFile); end
        if ~hadLab, dropLastLine(labFile); end
        error('markPlateBoxes:check', 'plate_boxes.csv and labels.csv disagree after adding %s (%s). The two new lines were removed.', f, msg);
    end
    nNew = nNew + strcmpi(note, 'night');
    fprintf('  %s added: box [%d %d %d %d], text %s, split %s, note %s.\n', f, box, txt, split, note);
    B = readtable(boxFile, 'TextType', 'string', 'Delimiter', ',');
    L = readtable(labFile, 'TextType', 'string', 'Delimiter', ',');
end
fprintf('\nDone. Check with run_tests, then train with:  train_real_model\n');
end

% ---------------------------------------------------------------------------------------
function appendLine(file, line)
txt = fileread(file);
fid = fopen(file, 'a');
if ~isempty(txt) && txt(end) ~= newline, fprintf(fid, '\n'); end
fprintf(fid, '%s\n', line);
fclose(fid);
end

function dropLastLine(file)
lines = splitlines(strtrim(fileread(file)));
fid = fopen(file, 'w');
fprintf(fid, '%s\n', strjoin(lines(1:end-1), newline));
fclose(fid);
end

function [ok, msg] = checkFiles(boxFile, labFile)
B = readtable(boxFile, 'TextType', 'string', 'Delimiter', ',');
L = readtable(labFile, 'TextType', 'string', 'Delimiter', ',');
ok = false;  msg = '';
if ~isequal(sort(B.file), sort(L.file))
    msg = 'the two files list different photos';  return
end
if ~all(B.w > 0 & B.h > 0 & B.x > 0 & B.y > 0)
    msg = 'a box has a non-positive size or position';  return
end
if any(cellfun(@isempty, regexp(cellstr(L.plate_text), '^[0-9A-Z]{3,9}$', 'once')))
    msg = 'a plate text is not 3-9 letters/digits';  return
end
ok = true;
end
