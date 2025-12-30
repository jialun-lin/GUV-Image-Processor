function [r, dims] = guvSeries_openReader(ND2Path, SeriesID, maxFrames)
%GUVSERIES_OPENREADER 打开 bf reader 并返回维度信息。
r = bfGetReader(ND2Path);
r.setSeries(SeriesID-1);

dims.H = r.getSizeY();
dims.W = r.getSizeX();
dims.T = r.getSizeT();
if nargin >= 3 && ~isempty(maxFrames)
    dims.T = min(dims.T, maxFrames);
end
end
