function [J, info] = normalizeExposure(I)
%NORMALIZEEXPOSURE  Repair photos that are too dark, too bright or too flat (Module 1).
%   [J, info] = NORMALIZEEXPOSURE(I)
%   A photo is treated only when its exposure looks abnormal - median luminance below
%   0.25 or above 0.75, or a 1 %..99 % luminance range narrower than 0.45; photos with
%   normal exposure are returned unchanged, so the correction cannot harm them.
%   Treatment: contrast stretch between the 1 % and 99 % luminance percentiles (the
%   same for all colour channels, so colours are kept), then a gamma correction that
%   moves the median luminance to 0.5 (gamma limited to 0.4 ... 2.5).
%   info.applied, info.median, info.range, info.gamma describe what was done.

I = toDouble(I);
Y = toGray(I);
q = min(floor(Y(:) * 256), 255) + 1;
cdf = cumsum(accumarray(q, 1, [256 1])) / numel(q);
lo  = (find(cdf >= 0.01, 1) - 1) / 255;
hi  = (find(cdf >= 0.99, 1) - 1) / 255;
med = (find(cdf >= 0.50, 1) - 1) / 255;
info = struct('applied', false, 'median', med, 'range', hi - lo, 'gamma', 1);
if med >= 0.25 && med <= 0.75 && (hi - lo) >= 0.45
    J = I;
    return
end
span = max(hi - lo, 0.1);
J = min(max((I - lo) / span, 0), 1);                       % contrast stretch (all channels alike)
m2 = min(max((med - lo) / span, 0.02), 0.98);
g = min(max(log(0.5) / log(m2), 0.4), 2.5);                % gamma that maps the median to 0.5
J = J .^ g;
info.applied = true;
info.gamma = g;
end
