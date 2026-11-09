function [mse, psnr] = imageMetrics(A, B)
%IMAGEMETRICS  Mean squared error and PSNR (dB) between two images in [0,1].

A = toDouble(A);  B = toDouble(B);
mse = mean((A(:) - B(:)).^2);
psnr = 10 * log10(1 / max(mse, eps));
end
