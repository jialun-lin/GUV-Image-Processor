function [FrameStoreInfo, frameGetter] = guvSeries_initFrameStore(OutSeries, dims, Cfg)
%GUVSERIES_INITFRAMESTORE 创建 Frames.h5 并返回 frameGetter 句柄（可为空）。
FrameStoreInfo = [];
frameGetter = [];
if ~Cfg.Output.SaveFrameStore
    return;
end

h5Path = fullfile(OutSeries, Cfg.Output.FrameStoreName);
guvIO_frameStoreCreateH5(h5Path, dims.H, dims.W, dims.T, Cfg.Output.FrameStoreDeflate);
frameGetter = @(tt) guvIO_frameStoreReadFrameH5(h5Path, tt);

FrameStoreInfo = struct();
FrameStoreInfo.h5Path = h5Path;
FrameStoreInfo.H = dims.H; FrameStoreInfo.W = dims.W; FrameStoreInfo.T = dims.T;
save(fullfile(OutSeries,'FrameStoreInfo.mat'), 'FrameStoreInfo');
end
