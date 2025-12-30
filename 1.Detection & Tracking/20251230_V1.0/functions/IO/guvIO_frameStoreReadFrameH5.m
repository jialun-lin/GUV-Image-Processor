function I = guvIO_frameStoreReadFrameH5(h5Path, t)
%GUVFRAMESTORE_READFRAMEH5 从 HDF5 图像仓库读取第 t 帧
% 说明：
%   h5read 的 count 参数需要明确的尺寸，因此这里用 persistent 缓存 H/W。

persistent cachedPath cachedHW

if isempty(cachedPath) || ~strcmp(cachedPath, h5Path) || isempty(cachedHW)
    info = h5info(h5Path, '/I');
    sz = info.Dataspace.Size;
    cachedHW = sz(1:2);
    cachedPath = h5Path;
end

H = cachedHW(1); W = cachedHW(2);
I = h5read(h5Path, '/I', [1 1 t], [H W 1]);
I = squeeze(I);
end
