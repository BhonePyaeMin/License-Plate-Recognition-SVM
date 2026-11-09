function V = plateSegVariants(mode, split)
%PLATESEGVARIANTS  The SEGMENTCHARS settings that SEGMENTPLATEBEST compares.
%   V = PLATESEGVARIANTS('full' | 'fast') returns a cell array; every element is a cell array of
%   SEGMENTCHARS options. The first element is always the default setting.
%     full : default | tilt search +-20 deg | threshold levels 0.6..1.25 of the Otsu level
%            computed from the middle of the crop, best row chosen, tilt search +-32 deg
%     fast : default | threshold-level sweep without tilt search (to rate many regions quickly)
%   V = PLATESEGVARIANTS('split') returns the RESCUE variants that cut touching characters apart ('Split', some with
%   a top-hat that removes lamp glare):
%   bold or blurred small plates (night photos) give blobs such as MH14 / TCF / 735 that no threshold
%   separates. They are tried by SEGMENTPLATEBEST only when the normal variants find fewer characters than
%   MinChars: as a competitor of the normal variants they cut good plates into wrong pieces (on plate crops of
%   the test photos exact plates fell from 4 to 1 of 16).
if nargin < 1, mode = 'full'; end
if strcmpi(mode, 'split')
    V = {{'Split', true, 'Select', 'row'}, {'Split', true, 'Select', 'row', 'SearchAngle', true}, ...
         {'Split', true, 'Select', 'row', 'LevelRegion', 'center', 'Levels', [0.7 0.9 1.1]}, ...
         {'Split', true, 'Select', 'row', 'TopHat', 0.18}, ...
         {'Split', true, 'Select', 'row', 'TopHat', 0.18, 'LevelRegion', 'center', 'Levels', [0.7 0.9 1.1]}};
    return
end
lv = [0.6 0.8 1 1.25];
if strcmpi(mode, 'fast')
    V = {{}, {'LevelRegion', 'center', 'Levels', lv, 'Select', 'row'}};
else
    V = {{}, {'SearchAngle', true}, ...
         {'LevelRegion', 'center', 'Levels', lv, 'Select', 'row', 'SearchAngle', true, 'AngleRange', 32}};
end
end
