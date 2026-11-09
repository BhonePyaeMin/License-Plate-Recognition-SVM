function BW = adaptiveThreshold(I, win, C, polarity)
%ADAPTIVETHRESHOLD  Local-mean thresholding, robust against uneven lighting.
%   BW = ADAPTIVETHRESHOLD(I, win, C, polarity)
%   win      : odd window size in pixels (default 25)
%   C        : offset in [0,1] subtracted from the local mean (default 0.05)
%   polarity : 'dark' (default) - foreground is darker than its surroundings
%              'bright'         - foreground is brighter than its surroundings

if nargin < 2 || isempty(win), win = 25; end
if nargin < 3 || isempty(C),   C = 0.05; end
if nargin < 4, polarity = 'dark'; end
I = toGray(I);
win = 2*floor(win/2) + 1;
r = (win-1)/2;
P = padImage(I, r, r, 'replicate');
M = conv2(ones(win,1)/win, ones(1,win)/win, P, 'valid');   % separable box mean
if strcmpi(polarity, 'dark')
    BW = I < M - C;
else
    BW = I > M + C;
end
end
