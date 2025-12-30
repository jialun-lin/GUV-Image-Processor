function MasterTable = GUV_Pipeline(Cfg)
% 自动把本脚本所在目录及其子目录加入 MATLAB 路径（避免找不到函数）
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(thisDir));
%GUV_PIPELINE  单入口GUV追踪Pipeline（模块化重构版，便于断点与团队协作）
% =========================================================================
% 入口规则：整个脚本包只建议从本文件启动。
%
% Pipeline 大阶段：
%   1) Series ：逐帧读ND2 → 每通道检测 → 同帧融合(选主ref) → 用主ref masks测所有通道强度 → 保存FramesMAT
%   2) Track  ：读取FramesMAT → guvTrack_trackCentroids（帧间关联+全局漂移估计）→ 输出 TTracks
%   3) IO     ：导出 per-series CSV + 汇总 MasterTable +（可选）Debug视频/TrackDiag
%
% 你最终确认的三条“语义规则”（实现时严格遵守）：
%   (A) 对象几何永远是“实心 innerMask 对象”（GUV填充区域），用于追踪与跨通道强度测量。
%   (B) 每帧双通道互为ref：若两通道都有对象，取 imfill 后面积更大者作为该对象的主ref mask。
%   (C) 所有通道强度(inner/mem/bg)统一用主ref mask测量；Cfg.Read.CType 仅用于构造 mask，不决定强度含义。
%
% 使用：
%   Cfg = guvPipeline_configDefault();
%   MasterTable = GUV_Pipeline(Cfg);

if nargin < 1 || isempty(Cfg)
    Cfg = guvPipeline_configDefault();
end

% -------------------- 基础检查 --------------------
if ~isfield(Cfg,'ND2Path') || ~exist(Cfg.ND2Path,'file')
    error('Cfg.ND2Path 无效：%s', string(Cfg.ND2Path));
end
if ~isfield(Cfg,'OutRoot') || isempty(Cfg.OutRoot)
    error('Cfg.OutRoot 为空，请在 guvPipeline_configDefault.m 中设置输出目录。');
end
if ~exist(Cfg.OutRoot,'dir'), mkdir(Cfg.OutRoot); end

% -------------------- 读取像素尺寸（若能从ND2 metadata获取则覆盖） --------------------
try
    Cfg.PixelSize_um = guvIO_tryReadPixelSize(Cfg.ND2Path, Cfg.PixelSize_um);
catch
    % 若读取失败，则使用用户手动填写的 PixelSize_um
end

% -------------------- 通道信息（CList/CNames/CType等） --------------------
Info = guvPipeline_getChannelInfo(Cfg);

% 统一写回 RefC / OtherC（避免下游字段缺失导致报错）
if ~isfield(Cfg,'Read'), Cfg.Read = struct(); end
Cfg.Read.RefC = Info.RefC;
Cfg.Read.RefName = Info.RefName;
if isfield(Info,'OtherC') && ~isempty(Info.OtherC)
    Cfg.Read.OtherC = Info.OtherC;
    Cfg.Read.OtherName = Info.OtherName;
else
    Cfg.Read.OtherC = [];
    Cfg.Read.OtherName = '';
end

% -------------------- 获取 SeriesCount --------------------
r0 = bfGetReader(Cfg.ND2Path);
TotalSeries = r0.getSeriesCount();
r0.close();

% -------------------- 生成 RunList（支持并行；单XY默认串行便于debug） --------------------
[RunList, isParallel] = guvSeries_getRunList(Cfg, TotalSeries);

fprintf('\n========== GUV_Pipeline ==========\n');
fprintf('ND2    : %s\n', Cfg.ND2Path);
fprintf('OutRoot: %s\n', Cfg.OutRoot);
fprintf('Series : total=%d, run=%d, parallel=%d\n', TotalSeries, numel(RunList), isParallel);
fprintf('CList  : %s\n', mat2str(Info.CList));
fprintf('CType  : %s\n', strjoin(string(Info.CType), ','));
fprintf('=================================\n\n');

AllT = cell(numel(RunList),1);

if isParallel
    parfor ii = 1:numel(RunList)
        sid = RunList(ii);
        AllT{ii} = guvPipeline_runOneSeries(sid, Cfg, Info);
    end
else
    for ii = 1:numel(RunList)
        sid = RunList(ii);
        AllT{ii} = guvPipeline_runOneSeries(sid, Cfg, Info);
    end
end

% -------------------- 对齐表格列并汇总（避免 vertcat 变量数不一致） --------------------
AllT = guvUtil_alignTablesForVertcat(AllT);
MasterTable = vertcat(AllT{:});

% -------------------- 输出 MasterTable --------------------
writetable(MasterTable, fullfile(Cfg.OutRoot,'GUV_MASTER_DB.csv'));
save(fullfile(Cfg.OutRoot,'GUV_MASTER_DB.mat'), 'MasterTable', 'Cfg', '-v7.3');

fprintf('\n[GUV_Pipeline] DONE. Master rows=%d\n', height(MasterTable));
end