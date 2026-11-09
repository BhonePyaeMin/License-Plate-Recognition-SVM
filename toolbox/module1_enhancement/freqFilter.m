function [J, H, spectrum] = freqFilter(I, type, cutoff, shape, order)
%FREQFILTER  Fourier-domain filtering (Module 1 - frequency domain).
%   [J, H, spectrum] = FREQFILTER(I, type, cutoff, shape, order)
%
%   type   : 'lowpass' | 'highpass' | 'bandpass'
%   cutoff : cut-off radius as a fraction (0..1) of the maximum frequency radius.
%            For 'bandpass' pass [low high].
%   shape  : 'ideal' | 'butterworth' (default) | 'gaussian'
%   order  : Butterworth order (default 2)
%
%   The image is zero-padded to 2Mx2N, transformed with fft2, multiplied by the
%   centred transfer function H(u,v), transformed back and cropped.
%   The DC term is kept for high/band-pass filters so the mean brightness stays.
%   Outputs: J filtered image, H transfer function, spectrum (log-magnitude
%   of the padded image's centred FFT, scaled to [0,1], for display).

if nargin < 3 || isempty(cutoff), cutoff = 0.2; end
if nargin < 4 || isempty(shape),  shape  = 'butterworth'; end
if nargin < 5 || isempty(order),  order  = 2; end
I = toDouble(I);
[M, N, nc] = size(I);
P = 2*M;  Q = 2*N;

% --- distance of every frequency sample from the centre of the shifted spectrum
[v, u] = meshgrid(-floor(Q/2):ceil(Q/2)-1, -floor(P/2):ceil(P/2)-1);
D = sqrt(u.^2 + v.^2);
Dmax = min(P, Q) / 2;

switch lower(type)
    case 'lowpass'
        H = lowpassResponse(D, cutoff(1)*Dmax, shape, order);
    case 'highpass'
        H = 1 - lowpassResponse(D, cutoff(1)*Dmax, shape, order);
    case 'bandpass'
        if numel(cutoff) < 2, cutoff = [cutoff(1)/2, cutoff(1)]; end
        lo = min(cutoff);  hi = max(cutoff);
        H = lowpassResponse(D, hi*Dmax, shape, order) - lowpassResponse(D, lo*Dmax, shape, order);
    otherwise
        error('freqFilter:type', 'Unknown filter type "%s".', type);
end
if ~strcmpi(type, 'lowpass')
    H(floor(P/2)+1, floor(Q/2)+1) = 1;                % keep DC (mean brightness)
end

J = zeros(M, N, nc);
spectrum = [];
for ch = 1:nc
    F = fftshift(fft2(I(:,:,ch), P, Q));              % zero-padded, centred spectrum
    if ch == 1
        S = log(1 + abs(F));
        spectrum = S / max(S(:));
    end
    g = real(ifft2(ifftshift(F .* H)));
    J(:,:,ch) = g(1:M, 1:N);
end
J = min(max(J, 0), 1);
end

function H = lowpassResponse(D, D0, shape, order)
D0 = max(D0, eps);
switch lower(shape)
    case 'ideal',       H = double(D <= D0);
    case 'butterworth', H = 1 ./ (1 + (D ./ D0).^(2*order));
    case 'gaussian',    H = exp(-(D.^2) ./ (2*D0^2));
    otherwise
        error('freqFilter:shape', 'Unknown filter shape "%s".', shape);
end
end
