function N = augmentGlyph(g)
%AUGMENTGLYPH  Turn a clean font glyph into a realistic, normalised training sample.
%   N = AUGMENTGLYPH(g) with g a uint8/double ink image (ink = bright).
%   The glyph is degraded the way a character on a photographed plate is:
%   random size, horizontal scaling (condensed to wide), shear and rotation (Module 3),
%   uneven contrast, camera blur and noise, optional low resolution, then Otsu
%   binarisation with a random offset of the level (varies the stroke weight)
%   (Module 2) and the same
%   NORMALIZECHAR step that is used at recognition time. Returns a 32x32 image.

g = toDouble(g);
% 1. random pixel height of the character as it would appear in a photo
hT = 20 + 40 * rand;
g = imResize(g, max(2, round(size(g) * hT / size(g,1))), 'bilinear');
% real plate typefaces range from condensed to wide: random horizontal scaling
g = imResize(g, [size(g, 1), max(2, round(size(g, 2) * (0.7 + 0.6 * rand)))], 'bilinear');
% 2. add margin, then random shear and rotation
m = ceil(0.3 * max(size(g))) + 2;
G = zeros(size(g) + 2*m);
G(m+1:end-m, m+1:end-m) = g;
G = geometricTransforms(G, 'shear', (rand - 0.5) * 0.36, 0, 'bilinear');
G = geometricTransforms(G, 'rotate', (rand - 0.5) * 16, 'bilinear');
% 3. photometric degradation: dark ink on a lighter plate
bg  = 0.6 + 0.35 * rand;
ink = 0.02 + 0.30 * rand;
img = bg - (bg - ink) * G;
if rand < 0.35                                             % low-resolution capture
    f = 0.4 + 0.4 * rand;
    img = imResize(imResize(img, f, 'bilinear'), size(img), 'bilinear');
end
sg = 0.3 + 1.1 * rand;
img = spatialFilter(img, gaussianKernel(2*ceil(3*sg) + 1, sg));
img = img + (0.07 * rand) * randn(size(img));
img = min(max(img, 0), 1);
% 4. binarise exactly as the recogniser does (dark characters = foreground)
level = otsuThreshold(img) + 0.12 * (rand - 0.5);          % moving the level varies the stroke weight
BW = img < level;
% drop specks left over from noise, keep the largest blobs
[L, n] = labelComponents(BW, 8);
if n > 1
    props = componentProps(L, n);
    keep = props.Area >= 0.15 * max(props.Area);
    BW = false(size(BW));
    BW(L > 0) = keep(L(L > 0));
end
N = normalizeChar(BW, 32);
end
