function fig = showPipeline(img, res, visible)
%SHOWPIPELINE  Figure with every stage of the plate recognition pipeline.
%   fig = SHOWPIPELINE(img, res) with res from RECOGNIZEPLATE.
%   fig = SHOWPIPELINE(img, res, 'off') creates the figure invisibly (for saving).
%   Panels: input + detected box, vertical edges, morphology blobs with the
%   candidate boxes, plate crop, de-skewed plate, binary image, segmented
%   characters and the 32x32 character images with the SVM reading.

if nargin < 3, visible = 'on'; end
img = toDouble(img);
fig = figure('Name', 'License plate recognition - pipeline', 'Color', 'w', ...
             'Position', [40 40 1300 820], 'Visible', visible);

ax = subplot(3, 3, 1);
showImage(ax, img, '1. Input and detected plate');
if ~isempty(res.bbox)
    rectangle(ax, 'Position', res.bbox, 'EdgeColor', 'r', 'LineWidth', 2);
end

if ~isempty(res.detectDebug)
    d = res.detectDebug;
    showImage(subplot(3, 3, 2), d.edges, '2. Vertical Sobel edges (Otsu)');
    ax = subplot(3, 3, 3);
    showImage(ax, d.blobs, '3. Closing + opening + hole fill');
    for k = 1:size(d.candidates, 1)
        rectangle(ax, 'Position', d.candidates(k,:), 'EdgeColor', 'y', 'LineWidth', 1);
    end
end

if ~isempty(res.plate)
    showImage(subplot(3, 3, 4), res.plate, '4. Plate crop');
end
if ~isempty(res.segDebug)
    s = res.segDebug;
    showImage(subplot(3, 3, 5), s.plate, sprintf('5. Resized + de-skewed (%.1f deg)', s.angle));
    showImage(subplot(3, 3, 6), s.binary, sprintf('6. Binary (%s characters)', s.polarity));
    ax = subplot(3, 3, 7);
    showImage(ax, s.plate, '7. Segmented characters');
    for k = 1:size(res.boxes, 1)
        rectangle(ax, 'Position', res.boxes(k,:), 'EdgeColor', [0 0.8 0], 'LineWidth', 1.5);
    end
end

ax = subplot(3, 3, [8 9]);
if ~isempty(res.chars)
    strip = [];
    for k = 1:numel(res.chars)
        strip = [strip, res.chars{k}, zeros(32, 4)]; %#ok<AGROW>
    end
    showImage(ax, 1 - strip, sprintf('8. SVM reading: %s', res.text));
    colormap(ax, gray);
else
    showImage(ax, ones(32, 64), '8. No characters found');
end
end
