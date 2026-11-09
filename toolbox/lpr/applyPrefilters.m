function [J, report] = applyPrefilters(I, chain, varargin)
%APPLYPREFILTERS  Run a list of pre-filters (see PREFILTEROPS) on a photo, one after the other.
%   [J, report] = APPLYPREFILTERS(I, chain, 'Name', value, ...)
%   chain : struct array with the fields  name (as in PREFILTEROPS)  and  p (vector of parameters);
%           an empty chain returns the photo unchanged. A field  enabled  (default true) switches a
%           stage off without deleting it.
%   Options: 'Pad'    border handling of the spatial filters: 'replicate' (default) | 'symmetric' | 'zero'
%            'Kernel' numeric matrix (odd size) for 'Convolution with my own kernel'
%   J      : the filtered photo (double, same colour type as the input; its size changes only with Resize)
%   report : cell array of text lines, one per stage that was run (name, parameters, time)
%   Example:  chain = struct('name', {'Median filter', 'Gamma correction'}, 'p', {3, 0.7});
%             J = applyPrefilters(img, chain);   res = recognizePlate(J, model);

p = inputParser;
p.addParameter('Pad', 'replicate');
p.addParameter('Kernel', [0 -1 0; -1 5 -1; 0 -1 0]);
p.parse(varargin{:});
o = p.Results;

J = toDouble(I);
report = {};
if isempty(chain), return; end
ops = prefilterOps();
names = {ops.name};
for k = 1:numel(chain)
    if isfield(chain, 'enabled') && ~isempty(chain(k).enabled) && ~chain(k).enabled, continue; end
    idx = find(strcmp(names, chain(k).name), 1);
    if isempty(idx), error('applyPrefilters:name', 'No pre-filter called "%s".', chain(k).name); end
    op = ops(idx);
    pv = zeros(1, max(1, numel(op.params)));
    given = chain(k).p(:).';
    for q = 1:numel(op.params)
        if q <= numel(given), pv(q) = given(q); else, pv(q) = op.params(q).default; end
        pv(q) = min(max(pv(q), op.params(q).min), op.params(q).max);
    end
    if strcmp(op.name, 'Convolution with my own kernel')
        if any(mod(size(o.Kernel), 2) == 0), error('applyPrefilters:kernel', 'The convolution kernel must have an odd number of rows and columns.'); end
        if ~isnumeric(o.Kernel) || ~all(isfinite(o.Kernel(:))), error('applyPrefilters:kernel', 'The convolution kernel must be a finite numeric matrix.'); end
    end
    t0 = tic;
    [J, info] = op.run(J, pv, o.Pad, o.Kernel);
    report{end+1} = sprintf('%d. %s: %s  [%.2f s]', numel(report) + 1, op.name, info, toc(t0)); %#ok<AGROW>
end
end
