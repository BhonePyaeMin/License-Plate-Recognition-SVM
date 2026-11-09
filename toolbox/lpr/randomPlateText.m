function [txt, fmt] = randomPlateText(fmt)
%RANDOMPLATETEXT  Random plate number following a letter/digit format.
%   [txt, fmt] = RANDOMPLATETEXT(fmt)  - fmt uses  L = letter, D = digit, space = gap.
%   With no argument a random format is chosen from a few common layouts.

formats = {'LLL DDDD', 'LL DDDD', 'DLL DDDD', 'LLL DDD', 'LL DD LLL', 'DDD LLL', 'LLLL DDD', 'DDDD LL'};
if nargin < 1 || isempty(fmt)
    fmt = formats{randi(numel(formats))};
end
letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
digits  = '0123456789';
txt = fmt;
for k = 1:numel(fmt)
    switch fmt(k)
        case 'L', txt(k) = letters(randi(numel(letters)));
        case 'D', txt(k) = digits(randi(numel(digits)));
    end
end
end
