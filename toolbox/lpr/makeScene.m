function [img, gt] = makeScene(tpl, variantIdx, varargin)
%MAKESCENE  Synthetic street photo of a car with a license plate (test data generator).
%   [img, gt] = MAKESCENE(tpl, variantIdx, 'Name', value, ...)
%   Options: 'Text'   plate text (default: random)
%            'Size'   [rows cols] of the scene (default [480 640])
%            'Format' plate format passed to RANDOMPLATETEXT
%            'Hard'   0..1, amount of rotation / blur / noise / dim light (default 0.5)
%   img : RGB double scene;  gt.text, gt.bbox = [x y w h] of the plate, gt.style.
%
%   The scene has a gradient sky, buildings, road, a car (windshield, headlights,
%   grille, bumper) and the plate, which is warped (Module 3), lit unevenly,
%   blurred and noisy. It exercises every stage of the recognition pipeline
%   without needing a photo collection.

p = inputParser;
p.addParameter('Text', '');
p.addParameter('Size', [480 640]);
p.addParameter('Format', '');
p.addParameter('Hard', 0.5);
p.parse(varargin{:});
H = p.Results.Size(1);  W = p.Results.Size(2);
hard = p.Results.Hard;
txt = p.Results.Text;
if isempty(txt), txt = randomPlateText(p.Results.Format); end
v = variantIdx(randi(numel(variantIdx)));

% ---------------- background: sky gradient, buildings, road -------------------
top = hsv2rgb([rand, 0.05 + 0.3*rand, 0.65 + 0.3*rand]);
mid = hsv2rgb([rand, 0.05 + 0.25*rand, 0.35 + 0.4*rand]);
t = linspace(0, 1, H).';
img = zeros(H, W, 3);
for ch = 1:3
    img(:,:,ch) = repmat((1-t) * top(ch) + t * mid(ch), 1, W);
end
for k = 1:randi([4 9])                                     % buildings / windows / signs
    c = hsv2rgb([rand, 0.1 + 0.4*rand, 0.3 + 0.6*rand]);
    h0 = randi([round(0.05*H), round(0.35*H)]);  w0 = randi([40, 160]);
    r0 = randi([1, round(0.55*H)]);              c0 = randi([1, W - w0]);
    img = fillRect(img, r0, r0 + h0, c0, c0 + w0, c, 1);
end
road = 0.28 + 0.2 * rand;
img = fillRect(img, round(0.80*H), H, 1, W, [road road road*1.05], 1);

% ---------------- car --------------------------------------------------------
cL = round(W * (0.10 + 0.10*rand));  cR = round(W * (0.78 + 0.12*rand));
cT = round(H * (0.22 + 0.06*rand));  cB = round(H * 0.86);
body = hsv2rgb([rand, 0.15 + 0.75*rand, 0.35 + 0.55*rand]);
img = fillRect(img, cT, cB, cL, cR, body, 1);
img = fillRect(img, cT + round(0.03*H), cT + round(0.20*H), cL + round(0.08*(cR-cL)), cR - round(0.08*(cR-cL)), ...
               [0.08 0.10 0.14] + 0.05*rand, 1);              % windshield
for side = [0 1]                                              % headlights
    cx = cL + round((0.14 + side * 0.72) * (cR - cL));
    img = fillEllipse(img, round(0.55*H), cx, round(0.045*H), round(0.07*W), [0.12 0.12 0.12], 1);
    img = fillEllipse(img, round(0.55*H), cx, round(0.032*H), round(0.05*W), [0.95 0.95 0.82], 1);
end
gw = round(0.40 * (cR - cL));  gx = round((cL + cR)/2) - round(gw/2);
img = fillRect(img, round(0.50*H), round(0.60*H), gx, gx + gw, [0.07 0.07 0.08], 1);   % grille
for yy = round(0.505*H):6:round(0.595*H)                      % grille slats
    img = fillRect(img, yy, yy + 1, gx, gx + gw, [0.35 0.35 0.38], 1);
end
bump = {[0.18 0.18 0.2], body * 0.8, [0.7 0.7 0.72]};
img = fillRect(img, round(0.69*H), round(0.84*H), cL, cR, bump{randi(3)}, 1);           % bumper
img = fillRect(img, round(0.84*H), round(0.87*H), cL, cR, [0.05 0.05 0.06], 1);          % under-bumper shadow

% ---------------- plate: render, scale, warp and composite -------------------
[plate, ~] = renderPlate(txt, tpl, v, 'Height', 110);
wTarget = 150 + 110 * rand;
plate = imResize(plate, wTarget / size(plate, 2), 'bilinear');
[hp, wp, ~] = size(plate);
ang = (rand - 0.5) * 2 * (2 + 8 * hard) * pi / 180;
shx = (rand - 0.5) * 2 * 0.10 * hard;
cx = W * (0.5 + 0.08 * (rand - 0.5) * 2);
cy = H * (0.70 + 0.04 * (rand - 0.5) * 2);
Tc0 = [1 0 -(wp+1)/2; 0 1 -(hp+1)/2; 0 0 1];
R   = [cos(ang) sin(ang) 0; -sin(ang) cos(ang) 0; 0 0 1];
Sh  = [1 shx 0; 0 1 0; 0 0 1];
T = [1 0 cx; 0 1 cy; 0 0 1] * R * Sh * Tc0;
warped = warpImage(plate, T, [H W], 'bilinear', 'reverse', 0);
alpha = warpImage(ones(hp, wp), T, [H W], 'bilinear', 'reverse', 0);
img = img .* (1 - alpha) + warped .* alpha;
[ry, rx] = find(alpha > 0.5);
gt.bbox = [min(rx), min(ry), max(rx) - min(rx) + 1, max(ry) - min(ry) + 1];
gt.text = strrep(txt, ' ', '');
gt.fullText = txt;
gt.format = regexprep(regexprep(txt, '[A-Z]', 'L'), '[0-9]', 'D');   % e.g. 'LLL DDDD'
gt.font = [tpl.variants{v,1} ' ' tpl.variants{v,2}];

% ---------------- camera effects --------------------------------------------
[gx2, gy2] = meshgrid(linspace(-1, 1, W), linspace(-1, 1, H));
shade = 1 + 0.30 * hard * (rand - 0.5) * 2 * gx2 + 0.20 * hard * (rand - 0.5) * 2 * gy2;
gain = 1 - 0.45 * hard * rand;
img = img .* repmat(shade * gain, [1 1 3]);
sg = 0.3 + 1.0 * hard * rand;
img = spatialFilter(img, gaussianKernel(2*ceil(3*sg) + 1, sg));
img = img + (0.005 + 0.03 * hard * rand) * randn(size(img));
img = min(max(img, 0), 1);
end

function img = fillRect(img, r0, r1, c0, c1, color, alpha)
[H, W, ~] = size(img);
r = max(1, round(r0)):min(H, round(r1));
c = max(1, round(c0)):min(W, round(c1));
if isempty(r) || isempty(c), return; end
for ch = 1:3
    img(r, c, ch) = (1 - alpha) * img(r, c, ch) + alpha * color(ch);
end
end

function img = fillEllipse(img, cy, cx, ry, rx, color, alpha)
[H, W, ~] = size(img);
[x, y] = meshgrid(1:W, 1:H);
m = ((x - cx) / rx).^2 + ((y - cy) / ry).^2 <= 1;
for ch = 1:3
    layer = img(:,:,ch);
    layer(m) = (1 - alpha) * layer(m) + alpha * color(ch);
    img(:,:,ch) = layer;
end
end
