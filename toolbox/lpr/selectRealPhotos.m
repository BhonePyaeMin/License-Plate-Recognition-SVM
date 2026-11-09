function m = selectRealPhotos(T, subset, group)
%SELECTREALPHOTOS  Rows of images/real/labels.csv that belong to a subset and a group of photos.
%   m = SELECTREALPHOTOS(T, subset, group) returns a logical column for the table T of labels.csv.
%   subset : 'dev' | 'test' | 'all'  (the split column)
%   group  : 'project' (default) the 49 photos of the project, 'openalpr' the 444 photos of the OpenALPR benchmark
%            (images/real/openalpr/, see images/real/SOURCES.md), 'all' both.
%   The default 'project' keeps every number measured before the OpenALPR photos were added reproducible.
if nargin < 3 || isempty(group), group = 'project'; end
isOA = startsWith(T.file, "openalpr/");
switch lower(group)
    case 'project',  g = ~isOA;
    case 'openalpr', g = isOA;
    case 'all',      g = true(height(T), 1);
    otherwise, error('selectRealPhotos:group', 'Unknown group "%s" (project, openalpr or all).', group);
end
if strcmpi(subset, 'all'), s = true(height(T), 1); else, s = T.split == string(lower(subset)); end
m = g & s;
end
