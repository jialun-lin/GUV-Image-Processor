function LocalTable = guvPipeline_runOneSeries(SeriesID, Cfg, Info)
%GUVPIPELINE_RUNONESERIES 处理单个 Series（一个 XY 视野）
% =========================================================================
% 本函数对应你要求的“一个大环节脚本串联本环节小函数”的风格：
%   Series(逐帧读图/检测/融合/保存) → Track(帧间关联生成TTracks) → IO(表格/视频/diag)
%
% 与旧版差异（但输出字段保持一致）：
%   - 不再“固定某个通道当 Ref masks”
%   - 每帧对每通道都做检测，然后同帧融合：
%       若两通道都有对象，则取 imfill 后面积更大者为主 ref mask
%   - 所有通道强度统一用主 ref mask 测量（inner/mem/bg），避免 CType 造成语义混乱
%
% 输入：
%   SeriesID : ND2 的 series index (MATLAB 1-based)
%   Cfg      : guvPipeline_configDefault 产生的配置
%   Info     : guvPipeline_getChannelInfo 解析出的通道信息（CList/CNames/CType等）
%
% 输出：
%   LocalTable : 本 series 的追踪结果表格（用于最终 MasterTable 拼接）

% -------------------- 打开 reader 并设置 series --------------------
[r, dims] = guvSeries_openReader(Cfg.ND2Path, SeriesID, Cfg.Debug.MaxFrames);

% -------------------- 输出目录（仍用一个固定通道名组织文件夹，避免目录爆炸） --------------------
% 注意：目录名只用于组织文件，不代表“mask ref 固定来自该通道”。
refC = Cfg.Read.RefC;
refIdx = find(Info.CList==refC, 1, 'first');
if isempty(refIdx), refIdx = 1; end
CName = Info.CNames{refIdx};

% 是否输出 debug（单XY调试）：批量处理时避免输出海量PNG/视频
nSel = inf;
% 注意：isfield 的第二个输入必须是字符向量/字符串。
% 这里使用明确的字段名字符串，避免出现 “函数或变量 'Read' 无法识别” 的语法错误。
if isfield(Cfg,'Read') && isfield(Cfg.Read,'SelectXYs') && ~isempty(Cfg.Read.SelectXYs)
    nSel = numel(Cfg.Read.SelectXYs);
end
usePar = isfield(Cfg,'Parallel') && isfield(Cfg.Parallel,'Enable') && Cfg.Parallel.Enable;
IsDebug = Cfg.Debug.Enable && (~Cfg.Debug.SingleXYOnly || nSel<=1) && ~usePar;
Paths = guvSeries_initOutputs(SeriesID, Cfg, IsDebug, refC, CName);

% -------------------- FrameStore（可选，避免保存每帧整图） --------------------
[FrameStoreInfo, frameGetter] = guvSeries_initFrameStore(Paths.OutSeries, dims, Cfg);

% -------------------- 阈值换算（um->px） --------------------
Thr = guvSeries_buildPxThresholds(Cfg);

% -------------------- DetectOpts（集中组装，便于断点调参） --------------------
DetectOpts = Cfg.Detect.Opts;
DetectOpts.pixel_size = Thr.px;

% 近邻去重/合并（仅对 CType==mem 生效）：参数通过 DetectOpts 下发到 detect 模块
DetectOpts.suppressClose.enable = isfield(Cfg.Detect,'SuppressCloseOnMem') && Cfg.Detect.SuppressCloseOnMem;
DetectOpts.suppressClose.dist_px = Thr.suppressDist_px;


% debug figure 开关：只在单XY调试时开启
if isfield(DetectOpts,'debug') && isfield(DetectOpts.debug,'makeFigure')
    DetectOpts.debug.makeFigure = false;
end

% -------------------- Series：逐帧检测 + 同帧融合 + 多通道强度测量 + 保存 FramesMAT --------------------
guvSeries_detectSaveLoop_fuseMainRef(r, dims, Cfg, Paths, Thr, DetectOpts, Info, FrameStoreInfo, IsDebug);

% -------------------- 关闭 reader --------------------
r.close();

% -------------------- Track：读取 FramesMAT → 生成 TTracks --------------------
TTracks = guvSeries_trackFromMats(Paths, Cfg, Thr, frameGetter);

% -------------------- Debug 视频（可选） --------------------
if IsDebug && Cfg.Debug.SaveVideo
    files = guvUtil_sortFrameFiles(dir(fullfile(Paths.OutFrames, 'Time_*_Data.mat')));
    guvSeries_makeDebugVideo(Paths, Cfg, files, TTracks, frameGetter);
end

% -------------------- 导出 per-series Table --------------------
LocalTable = guvSeries_exportTable(Paths, Cfg, TTracks);

end