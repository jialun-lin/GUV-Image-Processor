function [FrameStoreInfo, frameGetter] = guvSeries_initFrameStore(OutSeries, dims, Cfg)
%GUVSERIES_INITFRAMESTORE 创建 Frames.h5 并返回 frameGetter 句柄（可为空）。
FrameStoreInfo = [];
frameGetter = [];
if ~Cfg.Output.SaveFrameStore
    return;
end

h5Path = fullfile(OutSeries, Cfg.Output.FrameStoreName);
mode = 'ref';
if isfield(Cfg.Output,'FrameStoreMode') && ~isempty(Cfg.Output.FrameStoreMode)
    mode = char(Cfg.Output.FrameStoreMode);
end

% 始终创建 /I（用于“显示背景/兼容旧逻辑”）
guvIO_frameStoreCreateH5(h5Path, dims.H, dims.W, dims.T, Cfg.Output.FrameStoreDeflate, '/I', true);

datasets = {'/I'};
if strcmpi(mode,'multi')
    % 额外为每个通道创建 /I_Cxx（支持后续视频 Merge 在无 ND2 时导出）
    CList = Cfg.Read.CList(:)';
    for k = 1:numel(CList)
        ds = sprintf('/I_C%02d', CList(k));
        guvIO_frameStoreCreateH5(h5Path, dims.H, dims.W, dims.T, Cfg.Output.FrameStoreDeflate, ds, false);
        datasets{end+1} = ds; %#ok<AGROW>
    end
end

frameGetter = @(tt) guvIO_frameStoreReadFrameH5(h5Path, tt, '/I');

FrameStoreInfo = struct();
FrameStoreInfo.h5Path = h5Path;
FrameStoreInfo.H = dims.H; FrameStoreInfo.W = dims.W; FrameStoreInfo.T = dims.T;
FrameStoreInfo.Mode = mode;
FrameStoreInfo.CList = Cfg.Read.CList(:)';
FrameStoreInfo.Datasets = datasets;
save(fullfile(OutSeries,'FrameStoreInfo.mat'), 'FrameStoreInfo');
end
