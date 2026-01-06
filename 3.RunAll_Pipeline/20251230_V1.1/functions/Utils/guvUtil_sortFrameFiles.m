function files = guvUtil_sortFrameFiles(files)
%GUVSORTFRAMEFILES sort dir() output by Time_XXXX in filename

if isempty(files), return; end
names = {files.name};
idx = nan(size(names));
for i = 1:numel(names)
    tok = regexp(names{i}, 'Time_(\d+)_', 'tokens', 'once');
    if ~isempty(tok)
        idx(i) = str2double(tok{1});
    else
        idx(i) = i;
    end
end
[~, ord] = sort(idx);
files = files(ord);
end
