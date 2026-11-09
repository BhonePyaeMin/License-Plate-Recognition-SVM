function R = evaluateYaw(model, varargin)
%EVALUATEYAW  Exact-plate rate of synthetic plates seen from the side, with and without rectification.
%   R = EVALUATEYAW(model, 'Name', value, ...)
%   Plates are drawn with RENDERPLATE (fonts the SVM never saw if model comes from the hold-out run), put on
%   a grey "car body" and turned about the vertical axis by the yaw angle (a pinhole camera 3 plate widths
%   away; the plate foreshortens and its far edge shrinks: perspective, not just shear), then blurred and
%   noisy. RECOGNIZEPLATE reads the crop ('Plate' option, no search for the plate) with
%     'off'   no rectification (the old path)
%     'auto'  rectification used when the outline is plate-like, distorted and not worse
%     'force' always use the straightened plate when its outline is plate-like
%   Options: 'Angles' yaw angles in degrees (default [0 15 30 40])   'N' plates per angle (default 40)
%            'Seed' (default 11)   'Roll' maximum in-plane rotation added, degrees (default 0)
%            'Modes' which of the four readings to run (default 1:4); 'RectifyMin' for the automatic one
%            'Crop' 'tight' (default: the plate's bounding box + 6 %, what a detector hands over) | 'loose'
%                   (the plate in a grey surrounding, 3 times its size: this also tests how well a loose crop
%                   is tightened, not only the perspective)
%     'fixed' forced, and the outline is warped to a fixed 240 x 80 rectangle
%   R.rate (angles x 4), R.charAcc (angles x 4), R.modes, R.angles. Prints a table.

p = inputParser;
p.addParameter('Angles', [0 15 30 40]);
p.addParameter('N', 40);
p.addParameter('Seed', 11);
p.addParameter('Roll', 0);
p.addParameter('Crop', 'tight');
p.addParameter('Modes', 1:4);
p.addParameter('RectifyMin', 4);
p.parse(varargin{:});
o = p.Results;

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
tpl = buildGlyphTemplates(fullfile(root, 'models', 'glyph_templates.mat'));
fonts = find(tpl.isTest);
modes = {'off', 'auto', 'force', 'fixed'};         % fixed = forced, 240 x 80 rectangle
na = numel(o.Angles);
R = struct('angles', o.Angles, 'modes', {modes}, 'rate', nan(na, 4), 'charAcc', nan(na, 4), 'rectifiedShare', zeros(na, 1));
for a = 1:na
    rng(o.Seed + a);
    ok = zeros(1, 4);  ca = zeros(1, 4);  nr = 0;
    for k = 1:o.N
        txt = randomPlateText();
        [pl, ~] = renderPlate(txt, tpl, fonts(randi(numel(fonts))), 'Height', 90 + randi(30), 'Style', 'white');
        img = yawPlate(pl, o.Angles(a), (rand - 0.5) * 2 * o.Roll, o.Crop);
        truth = strrep(txt, ' ', '');                            % the plate text has a gap, the reading has not
        for m = o.Modes
            if m == 4, r = recognizePlate(img, model, 'Plate', img, 'Rectify', 'force', 'RectifySize', [80 240]);
            else,      r = recognizePlate(img, model, 'Plate', img, 'Rectify', modes{m}, 'RectifyMin', o.RectifyMin); end
            ok(m) = ok(m) + strcmp(r.text, truth);
            ca(m) = ca(m) + max(0, 1 - editDistance(r.text, truth) / numel(truth));
            if m == 2, nr = nr + r.rectified; end
        end
    end
    R.rate(a, o.Modes) = ok(o.Modes) / o.N;  R.charAcc(a, o.Modes) = ca(o.Modes) / o.N;  R.rectifiedShare(a) = nr / o.N;
end
fprintf('Synthetic plates turned about the vertical axis (%d per angle): exact plates / character accuracy\n', o.N);
fprintf('  yaw    no rectification    auto (used in %%)      forced            forced, fixed 240x80\n');
for a = 1:na
    fprintf('  %2d     %5.1f %% / %4.1f %%     %5.1f %% / %4.1f %% (%3.0f %%)   %5.1f %% / %4.1f %%   %5.1f %% / %4.1f %%\n', o.Angles(a), ...
        100 * R.rate(a, 1), 100 * R.charAcc(a, 1), 100 * R.rate(a, 2), 100 * R.charAcc(a, 2), 100 * R.rectifiedShare(a), ...
        100 * R.rate(a, 3), 100 * R.charAcc(a, 3), 100 * R.rate(a, 4), 100 * R.charAcc(a, 4));
end
end

function img = yawPlate(pl, yawDeg, rollDeg, crop)
% put the plate on a grey background, turn it about the vertical axis and add blur and noise
[h, w, ~] = size(pl);
mx = round(0.18 * w);  my = round(0.5 * h);
bg = 0.45 + 0.1 * rand;
canvas = bg * ones(h + 2 * my, w + 2 * mx, 3);
canvas(my+1:my+h, mx+1:mx+w, :) = pl;
[H, W, ~] = size(canvas);
c = [(W + 1) / 2, (H + 1) / 2];
corners = [1 1; W 1; W H; 1 H] - c;                              % centred corners of the whole picture
phi = yawDeg * pi / 180;
f = 3 * w;                                                       % focal length: camera 3 plate widths away
Z = corners(:, 1) * sin(phi);                                    % depth change of the turned plane
X = corners(:, 1) * cos(phi);
dst = [f * X ./ (f + Z), f * corners(:, 2) ./ (f + Z)];
rho = rollDeg * pi / 180;
dst = dst * [cos(rho) sin(rho); -sin(rho) cos(rho)] + c;
H3 = homography([1 1; W 1; W H; 1 H], dst);
img = warpImage(canvas, H3, [H W], 'bilinear', 'reverse', bg);
sg = 0.5 + 0.8 * rand;
img = spatialFilter(img, gaussianKernel(2 * ceil(3 * sg) + 1, sg));
img = min(max(img + 0.02 * randn(size(img)), 0), 1);
if strcmpi(crop, 'tight')                                        % what a plate detector would hand over: the plate's bounding box + 6 %
    pc = H3 * [mx + 1, mx + w, mx + w, mx + 1; my + 1, my + 1, my + h, my + h; 1 1 1 1];
    px = pc(1, :) ./ pc(3, :);  py = pc(2, :) ./ pc(3, :);
    mgx = 0.06 * (max(px) - min(px));  mgy = 0.06 * (max(py) - min(py));
    c0 = max(1, floor(min(px) - mgx));  c1 = min(W, ceil(max(px) + mgx));
    r0 = max(1, floor(min(py) - mgy));  r1 = min(H, ceil(max(py) + mgy));
    img = img(r0:r1, c0:c1, :);
end
end
