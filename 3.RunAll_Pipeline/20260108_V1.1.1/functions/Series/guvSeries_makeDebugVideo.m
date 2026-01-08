function guvSeries_makeDebugVideo(Paths, Cfg, files, TTracks, frameGetter)
%GUVSERIES_MAKEDEBUGVIDEO 生成 MP4 调试视频（双通道各一份底图）。
% =========================================================================
% 你提出的需求：
%   - 保存两份视频：一份以 RefC 为底图，一份以 OtherC 为底图
%   - 叠加内容（由 guvDebug_makeDebugVideo 决定）：轨迹、ID、可选轮廓等
%
% 说明：
%   - Ref 底图优先使用 FrameStore 的 frameGetter（如果有），避免重复读取 ND2
%   - Other 底图通常需要从 ND2 读取（FrameStore 默认只存 RefC）

if nargin < 5, frameGetter = []; end
if isempty(files)
    return;
end
if isempty(TTracks)
    return;
end

refC = Cfg.Read.RefC;
otherC = [];
if isfield(Cfg,'Read') && isfield(Cfg.Read,'OtherC') && ~isempty(Cfg.Read.OtherC)
    otherC = Cfg.Read.OtherC;
end

saveBoth = true;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'SaveVideoBoth')
    saveBoth = logical(Cfg.Debug.SaveVideoBoth);
end

% 输出文件名（不再按通道建文件夹，但文件名注明底图通道）
mp4Ref = fullfile(Paths.OutVideo, sprintf('%s_Debug_refC%02d.mp4', Paths.SeriesName, refC));

% -------- Ref 视频：底图获取函数 --------
useBFForRef = isempty(frameGetter);
r = [];
if useBFForRef || (~isempty(otherC))
    r = bfGetReader(Cfg.ND2Path);
    r.setSeries(Paths.SeriesID - 1);     % Bio-Formats 0-based
end
z = Cfg.Read.Z;

if useBFForRef
    getRef = @(t) bfGetPlaneAtZCT(r, z, refC, t);
else
    getRef = frameGetter;  % FrameStore: 只读 RefC
end

guvDebug_makeDebugVideo(files, TTracks, Cfg, mp4Ref, Paths.SeriesName, getRef);

% -------- Other 视频（若存在）--------
if ~isempty(otherC) && saveBoth
    mp4Oth = fullfile(Paths.OutVideo, sprintf('%s_Debug_othC%02d.mp4', Paths.SeriesName, otherC));
    getOth = @(t) bfGetPlaneAtZCT(r, z, otherC, t);
    guvDebug_makeDebugVideo(files, TTracks, Cfg, mp4Oth, Paths.SeriesName, getOth);
end

if ~isempty(r)
    r.close();
end
end
