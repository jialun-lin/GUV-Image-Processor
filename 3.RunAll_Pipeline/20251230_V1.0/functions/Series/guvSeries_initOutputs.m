function P = guvSeries_initOutputs(SeriesID, Cfg, IsDebug, C, CName)
%GUVSERIES_INITOUTPUTS 统一创建输出目录并返回路径结构体。
SeriesName = sprintf('%s%03d', Cfg.SeriesPrefix, SeriesID);
% 输出目录：只到 XY(Series) 层级（不再按通道分文件夹）
OutSeries = fullfile(Cfg.OutRoot, SeriesName);
OutFrames = fullfile(OutSeries, 'FramesMAT');
OutDebug  = fullfile(OutSeries, 'Debug');
OutVideo  = fullfile(OutSeries, 'DebugVideo');

if ~exist(OutSeries,'dir'), mkdir(OutSeries); end
if Cfg.Output.SavePerFrameMAT && ~exist(OutFrames,'dir'), mkdir(OutFrames); end
if IsDebug && ~exist(OutDebug,'dir'), mkdir(OutDebug); end
if IsDebug && ~exist(OutVideo,'dir'), mkdir(OutVideo); end

P = struct();
P.SeriesID = SeriesID;
P.SeriesName = SeriesName;
P.C = C;
P.CName = CName;
P.OutSeries = OutSeries;
P.OutFrames = OutFrames;
P.OutDebug = OutDebug;
P.OutVideo = OutVideo;
end