function fig = compareEdgeDetectors(I)
%COMPAREEDGEDETECTORS  Side-by-side comparison of Sobel, Prewitt and Canny.
%   fig = COMPAREEDGEDETECTORS(I) also prints the number of edge pixels found.

G = toGray(I);
[Es, ms] = edgeDetect(G, 'sobel');
[Ep, mp] = edgeDetect(G, 'prewitt');
[Ec, mc] = edgeDetect(G, 'canny');
fig = figure('Name', 'Module 2 - Edge detector comparison', 'Color', 'w', 'Position', [60 60 1200 650]);
showImage(subplot(2,4,1), G, 'Original');
showImage(subplot(2,4,2), ms / max(ms(:)), 'Sobel gradient magnitude');
showImage(subplot(2,4,3), mp / max(mp(:)), 'Prewitt gradient magnitude');
showImage(subplot(2,4,4), mc / max(mc(:)), 'Canny gradient magnitude');
showImage(subplot(2,4,6), Es, sprintf('Sobel edges (%d px)', nnz(Es)));
showImage(subplot(2,4,7), Ep, sprintf('Prewitt edges (%d px)', nnz(Ep)));
showImage(subplot(2,4,8), Ec, sprintf('Canny edges (%d px)', nnz(Ec)));
end
