function S = collectRealChars(varargin)
%COLLECTREALCHARS  Harvest labelled character images from the real photos.
%   S = COLLECTREALCHARS('Name', value, ...)
%   For every photo of the chosen subset the plate region (the hand-marked box of
%   images/real/plate_boxes.csv, then the candidates found by DETECTPLATE) is segmented with
%   SEGMENTCHARS using the settings of PLATESEGVARIANTS. The first region/setting whose number
%   of characters equals the length of the known plate text provides the characters,
%   which are labelled left to right with that text. Photos where no region has the
%   right number of characters are skipped (their text is not used for training).
%   Options: 'Subset' 'dev' (default) | 'test' | 'all' - use 'dev' for training
%            'Group'  'project' (default) | 'openalpr' | 'all' (SELECTREALPHOTOS)
%            'Folder' folder with the photos and labels.csv (default images/real)
%            'UseBoxes' true (default): try the hand-marked plate boxes first
%   S.X      n x 324 HOG features        S.y   n x 1 class index (1..36)
%   S.imgs   32x32xn normalised characters (double, ink = 1)
%   S.photo  n x 1 string, the photo each character comes from
%   S.skipped  photos without a usable segmentation

p = inputParser;
p.addParameter('Subset', 'dev');
p.addParameter('Group', 'project');
p.addParameter('Folder', '');
p.addParameter('UseBoxes', true);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if isempty(o.Folder), o.Folder = fullfile(root, 'images', 'real'); end
charset = ['0':'9', 'A':'Z'];
T = readtable(fullfile(o.Folder, 'labels.csv'), 'TextType', 'string', 'Delimiter', ',');
T = T(selectRealPhotos(T, o.Subset, o.Group), :);

PB = [];
if o.UseBoxes && exist(fullfile(o.Folder, 'plate_boxes.csv'), 'file')
    PB = readtable(fullfile(o.Folder, 'plate_boxes.csv'), 'TextType', 'string');
end
% imgs starts as a 32x32x0 array: appending to [] with end+1 would skip slice 1
S = struct('X', [], 'y', [], 'imgs', zeros(32, 32, 0), 'photo', strings(0, 1), 'skipped', strings(0, 1));
for k = 1:height(T)
    img = imread(fullfile(o.Folder, T.file(k)));
    truth = char(T.plate_text(k));
    regions = zeros(0, 4);
    if o.UseBoxes && ~isempty(PB)
        g = PB{PB.file == T.file(k), {'x', 'y', 'w', 'h'}};
        if ~isempty(g), regions = g(1, :); end
    end
    got = false;
    for pass = 1:2                                          % pass 1: the hand-marked box; pass 2 (only if that failed): the candidates of DETECTPLATE
        if pass == 2
            [~, ~, dbg] = detectPlate(img, 'TopK', 15);
            cands = dbg.all;
            regions = zeros(0, 4);
            if ~isempty(cands)
                [~, order] = sort([cands.verify], 'descend');
                for i = order, regions(end+1, :) = cands(i).box; end %#ok<AGROW>
            end
        end
        for i = 1:size(regions, 1)
            b = regions(i, :);
            r = max(1, round(b(2))):min(size(img, 1), round(b(2) + b(4) - 1));
            c = max(1, round(b(1))):min(size(img, 2), round(b(1) + b(3) - 1));
            crop = toDouble(img(r, c, :));
            for v = plateSegVariants('full')
                [chars, ~] = segmentChars(crop, v{1}{:});
                if numel(chars) == numel(truth), break, end
            end
            if numel(chars) == numel(truth)
                for q = 1:numel(chars)
                    S.X(end+1, :) = hogFeatures(chars{q}); %#ok<AGROW>
                    S.y(end+1, 1) = find(charset == truth(q)); %#ok<AGROW>
                    S.imgs(:, :, end+1) = chars{q}; %#ok<AGROW>
                    S.photo(end+1, 1) = T.file(k); %#ok<AGROW>
                end
                got = true;
                break
            end
        end
        if got, break, end
    end
    if ~got, S.skipped(end+1, 1) = T.file(k); end
end
fprintf('%d characters from %d of %d photos (%d skipped)\n', numel(S.y), numel(unique(S.photo)), height(T), numel(S.skipped));
end
