function MasterTable = GUV_Pipeline(varargin)
%GUV_PIPELINE  单入口GUV追踪Pipeline（主流程）
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
% 支持两种调用方式（兼容旧版 + 支持 JSON）：
%   (A) 旧版：
%       Cfg = guvPipeline_configDefault();
%       MasterTable = GUV_Pipeline(Cfg);
%   (B) 新版：
%       MasterTable = GUV_Pipeline(InputPath, OutputPath);
%       MasterTable = GUV_Pipeline(InputPath, OutputPath, jsonPath);
%       MasterTable = GUV_Pipeline(InputPath, OutputPath, CfgStruct);

% 自动把本脚本所在目录及其子目录加入 MATLAB 路径（避免找不到函数）
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(thisDir));

% -------------------- 解析输入参数 --------------------
Cfg = [];
InputPath = '';
OutputPath = '';
cfgUser = struct();

if nargin == 1 && isstruct(varargin{1})
    % 旧版：直接传入 Cfg
    Cfg = varargin{1};
    if ~isfield(Cfg,'ND2Path') || ~isfield(Cfg,'OutRoot')
        error('旧版调用需要 Cfg.ND2Path 与 Cfg.OutRoot。');
    end
    InputPath  = Cfg.ND2Path;
    OutputPath = Cfg.OutRoot;
else
    if nargin < 2
        error('新版调用需要：GUV_Pipeline(InputPath, OutputPath, [CfgOrJson])');
    end
    InputPath  = char(varargin{1});
    OutputPath = char(varargin{2});

    % 第三个参数可选：JSON 路径 或 Cfg struct
    if nargin >= 3 && ~isempty(varargin{3})
        if isstruct(varargin{3})
            cfgUser = varargin{3};
        else
            cfgUser = guvPipeline_LoadConfig(char(varargin{3}));
        end
    else
        % 自动在 OutputPath / 脚本目录下寻找配置 JSON（有就覆盖默认）
        cfgPath = localFindConfigJson(OutputPath, thisDir);
        if ~isempty(cfgPath)
            cfgUser = guvPipeline_LoadConfig(cfgPath);
        else
            % 若未找到 JSON：自动在输出目录生成一个“完整默认配置”的 JSON，
            % 其字段与 guvPipeline_configDefault() 保持一致，便于用户直接编辑。
            try
                outJson = fullfile(OutputPath, 'guvPipeline_config.json');
                guvPipeline_writeDefaultConfigJson(outJson);
                fprintf('[GUV_Pipeline] 未找到配置 JSON，已生成默认配置：%s\n', outJson);
            catch ME
                warning('[GUV_Pipeline] Failed to auto-generate default JSON: %s', ME.message);
            end
        end
    end

    % 默认配置（含备注最全，便于用户查看）作为基线
    cfgDef = guvPipeline_configDefault();
    Cfg = localDeepMerge(cfgDef, cfgUser);
    % 入口参数优先覆盖路径（避免 JSON/默认里写死）
    Cfg.ND2Path = InputPath;
    Cfg.OutRoot = OutputPath;
end

% -------------------- 基础检查 --------------------
if ~exist(Cfg.ND2Path,'file')
    error('InputPath 无效：%s', string(Cfg.ND2Path));
end
if isempty(Cfg.OutRoot)
    error('OutputPath 为空，请传入输出目录。');
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
    localEnsureParpool(Cfg);
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

% -------------------- 汇总 Computation/AllResults.csv（AllXYResults.csv） --------------------
% 若每个 XY 目录下存在：XY###/Computation/AllResults.csv
% 则在输出根目录生成：OutRoot/AllXYResults.csv
try
    AllXYResults = guvCompute_collectAllXYResults(Cfg.OutRoot, Cfg.SeriesPrefix);
    save(fullfile(Cfg.OutRoot,'AllXYResults.mat'), 'AllXYResults', '-v7.3');
catch ME
    warning('Collect AllXYResults.csv failed: %s', ME.message);
end

% -------------------- 视频导出（独立模块 Pipeline；可单独运行） --------------------
try
    if isfield(Cfg,'Video') && isfield(Cfg.Video,'Enable') && Cfg.Video.Enable
        if ~isfield(Cfg.Video,'When') || strcmpi(string(Cfg.Video.When),'after')
            % 仅调用独立视频导出 Pipeline（细节全部在 GUV_VideoPipeline 内部）
            GUV_VideoPipeline(Cfg.OutRoot, Cfg);
        end
    end
catch ME
    warning('Video export failed: %s', ME.message);
end

fprintf('\n[GUV_Pipeline] DONE. Master rows=%d\n', height(MasterTable));
end

% =====================================================================
% Local helpers (仅本文件使用)
% =====================================================================

function cfgPath = localFindConfigJson(OutputPath, thisDir)
% 在输出目录（优先）与脚本目录中查找配置 JSON
cands = { ...
    fullfile(OutputPath, 'guvPipeline_config.json'), ...
    fullfile(OutputPath, 'config.json'), ...
    fullfile(thisDir,    'guvPipeline_config.json'), ...
    fullfile(thisDir,    'config.json') ...
    };

cfgPath = '';
for k = 1:numel(cands)
    if exist(cands{k},'file')
        cfgPath = cands{k};
        return;
    end
end
end

function out = localDeepMerge(def, user)
% 递归合并结构体：user 覆盖 def
out = def;
if isempty(user)
    return;
end
if ~isstruct(user)
    out = user;
    return;
end
fns = fieldnames(user);
for i = 1:numel(fns)
    fn = fns{i};
    uv = user.(fn);
    if isfield(out, fn) && isstruct(out.(fn)) && isstruct(uv)
        out.(fn) = localDeepMerge(out.(fn), uv);
    else
        out.(fn) = uv;
    end
end
end

function localEnsureParpool(Cfg)
% 按 Cfg.Parallel.PoolSize 限制并行池大小（便于按内存手动控并发）
if ~isfield(Cfg,'Parallel') || ~isfield(Cfg.Parallel,'Enable') || ~Cfg.Parallel.Enable
    return;
end
poolSize = [];
if isfield(Cfg.Parallel,'PoolSize')
    poolSize = Cfg.Parallel.PoolSize;
end

try
    p = gcp('nocreate');
catch
    % 无并行工具箱或不可用
    return;
end

% 获取本机最大 worker 数
try
    c = parcluster('local');
    maxW = c.NumWorkers;
catch
    maxW = [];
end

if isempty(poolSize) || ~isfinite(poolSize) || poolSize <= 0
    desired = maxW;
else
    desired = poolSize;
    if ~isempty(maxW)
        desired = min(desired, maxW);
    end
end

if isempty(desired) || desired <= 0
    return;
end

if isempty(p)
    parpool('local', desired);
else
    if p.NumWorkers ~= desired
        delete(p);
        parpool('local', desired);
    end
end
end
