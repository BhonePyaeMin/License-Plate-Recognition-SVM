function J = warpImage(I, T, outSize, method, mapping, fillVal)
%WARPIMAGE  Geometric warp by a 3x3 homogeneous transform (forward or reverse mapping).
%   J = WARPIMAGE(I, T, outSize, method, mapping, fillVal)
%   T       : 3x3 matrix acting on [x; y; 1] (x = column, y = row, 1-based)
%             that maps INPUT coordinates to OUTPUT coordinates. T may be affine or
%             projective (third row [g h 1]): the result is divided by the third
%             component, so the matrix from HOMOGRAPHY (perspective correction) works.
%   outSize : [rows cols] of the result (default size(I))
%   method  : 'nearest' | 'bilinear' | 'bicubic'
%   mapping : 'reverse' (default) - for every output pixel look up the source with
%             inv(T) and interpolate -> no holes.
%             'forward' - push every input pixel to T*[x;y;1] (nearest = write one
%             pixel, bilinear = splat to 4 pixels with weights). Leaves holes when
%             the image is enlarged; shown to illustrate why reverse mapping is used.
%   fillVal : value for pixels with no source (default 0)

if nargin < 3 || isempty(outSize), outSize = [size(I,1) size(I,2)]; end
if nargin < 4 || isempty(method),  method = 'bilinear'; end
if nargin < 5 || isempty(mapping), mapping = 'reverse'; end
if nargin < 6, fillVal = 0; end
I = toDouble(I);
[h, w, nc] = size(I);
H = outSize(1);  W = outSize(2);

switch lower(mapping)
    case 'reverse'
        [xo, yo] = meshgrid(1:W, 1:H);
        S = T \ [xo(:).'; yo(:).'; ones(1, numel(xo))];      % source coordinates
        Xs = reshape(S(1,:) ./ S(3,:), H, W);
        Ys = reshape(S(2,:) ./ S(3,:), H, W);
        J = interpSample(I, Xs, Ys, method, fillVal);

    case 'forward'
        [xi, yi] = meshgrid(1:w, 1:h);
        D = T * [xi(:).'; yi(:).'; ones(1, numel(xi))];
        Xd = D(1,:).' ./ D(3,:).';   Yd = D(2,:).' ./ D(3,:).';
        J = fillVal * ones(H, W, nc);
        for ch = 1:nc
            A = I(:,:,ch);
            if strcmpi(method, 'nearest')
                xr = round(Xd);  yr = round(Yd);
                ok = xr >= 1 & xr <= W & yr >= 1 & yr <= H;
                O = fillVal * ones(H, W);
                O(sub2ind([H W], yr(ok), xr(ok))) = A(ok);
            else                                              % bilinear splatting
                x0 = floor(Xd);  y0 = floor(Yd);
                fx = Xd - x0;    fy = Yd - y0;
                acc = zeros(H*W, 1);  wsum = zeros(H*W, 1);     % column accumulators (linear index)
                for oy = 0:1
                    for ox = 0:1
                        wgt = (ox*fx + (1-ox)*(1-fx)) .* (oy*fy + (1-oy)*(1-fy));
                        xr = x0 + ox;  yr = y0 + oy;
                        ok = xr >= 1 & xr <= W & yr >= 1 & yr <= H;
                        lin = sub2ind([H W], yr(ok), xr(ok));
                        acc  = acc  + accumarray(lin, wgt(ok) .* A(ok), [H*W 1]);
                        wsum = wsum + accumarray(lin, wgt(ok),          [H*W 1]);
                    end
                end
                acc = reshape(acc, H, W);  wsum = reshape(wsum, H, W);
                O = fillVal * ones(H, W);
                has = wsum > 1e-6;
                O(has) = acc(has) ./ wsum(has);
            end
            J(:,:,ch) = O;
        end
    otherwise
        error('warpImage:mapping', 'Mapping must be "reverse" or "forward".');
end
J = min(max(J, 0), 1);
end
