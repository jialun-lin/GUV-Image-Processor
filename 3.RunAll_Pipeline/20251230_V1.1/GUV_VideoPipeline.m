function outFiles = GUV_VideoPipeline(varargin)
%GUV_VIDEOPIPELINE  独立“视频导出 Pipeline”入口
% =========================================================================
% 设计目标：
%   - 可在主 GUV_Pipeline 结束后自动调用；
%   - 也可在主流程跑完后，基于已有的 FrameStore 单独运行（无需重新识别/追踪）。
%
% 支持调用方式：
%   (A) 仅给输出目录（自动找 JSON，可无 JSON）：
%       outFiles = GUV_VideoPipeline(OutputPath);
%   (B) 指定 JSON 或 Cfg 结构体覆盖默认：
%       outFiles = GUV_VideoPipeline(OutputPath, jsonPath);
%       outFiles = GUV_VideoPipeline(OutputPath, CfgStruct);
%   (C) 直接传入旧版 Cfg（使用 Cfg.OutRoot）：
%       outFiles = GUV_VideoPipeline(Cfg);
%
% 关键依赖：
%   - 优先使用 XY*/FrameStore.h5（Cfg.Output.FrameStoreName）
%   - 若 Cfg.Output.FrameStoreMode='multi'，将包含 /I_Cxx 数据集，支持 Merge 视频在无 ND2 时导出。

% addpath
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(thisDir));

outFiles = {};

% -------------------- 解析输入 --------------------
Cfg = [];
OutRoot = '';
cfgUser = struct();

if nargin < 1
    error('GUV_VideoPipeline:MissingInput', '缺少输入：OutputPath 或 Cfg。');
end

if isstruct(varargin{1})
    Cfg = varargin{1};
    if ~isfield(Cfg,'OutRoot') || isempty(Cfg.OutRoot)
        error('GUV_VideoPipeline:BadCfg', 'Cfg.OutRoot 为空。');
    end
    OutRoot = char(Cfg.OutRoot);
else
    OutRoot = char(varargin{1});
    if nargin >= 2 && ~isempty(varargin{2})
        if isstruct(varargin{2})
            cfgUser = varargin{2};
        else
            cfgUser = guvPipeline_LoadConfig(char(varargin{2}));
        end
    else
        cfgPath = localFindConfigJson(OutRoot, thisDir);
        if ~isempty(cfgPath)
            cfgUser = guvPipeline_LoadConfig(cfgPath);
        end
    end
end

% 统一构造 Cfg（默认配置作为基线；便于保留备注/参数说明）
if isempty(Cfg)
    cfgDef = guvPipeline_configDefault();
    Cfg = localDeepMerge(cfgDef, cfgUser);
end

% OutRoot 入口参数优先
Cfg.OutRoot = OutRoot;
if ~exist(Cfg.OutRoot,'dir')
    error('GUV_VideoPipeline:BadOutRoot', '输出目录不存在：%s', Cfg.OutRoot);
end

% 若用户显式调用视频 Pipeline，则即便 Cfg.Video.Enable=false 也执行一次
if ~isfield(Cfg,'Video') || ~isfield(Cfg.Video,'Tasks')
    error('GUV_VideoPipeline:MissingVideoCfg', 'Cfg.Video 配置缺失。请检查 guvPipeline_configDefault.m 或 JSON。');
end

% -------------------- 收集要导出的 XY 列表 --------------------
prefix = 'XY';
if isfield(Cfg,'SeriesPrefix') && ~isempty(Cfg.SeriesPrefix)
    prefix = char(Cfg.SeriesPrefix);
end

xyDirs = dir(fullfile(Cfg.OutRoot, sprintf('%s*', prefix)));
xyDirs = xyDirs([xyDirs.isdir]);

% 仅保留类似 XY001 这类目录
keep = false(size(xyDirs));
sidAll = nan(size(xyDirs));
for k = 1:numel(xyDirs)
    name = xyDirs(k).name;
    tok = regexp(name, sprintf('^%s(\\d+)$', prefix), 'tokens', 'once');
    if ~isempty(tok)
        keep(k) = true;
        sidAll(k) = str2double(tok{1});
    end
end
xyDirs = xyDirs(keep);
sidAll = sidAll(keep);

if isempty(xyDirs)
    warning('未找到任何 %s### 目录：%s', prefix, Cfg.OutRoot);
    return;
end

% 用户指定 SeriesList 优先
sidRun = sidAll;
if isfield(Cfg.Video,'SeriesList') && ~isempty(Cfg.Video.SeriesList)
    sidReq = Cfg.Video.SeriesList(:)';
    sidRun = intersect(sidAll, sidReq, 'stable');
end

% -------------------- 并行池（可选） --------------------
usePar = false;
if isfield(Cfg,'Parallel') && isfield(Cfg.Parallel,'Enable')
    usePar = logical(Cfg.Parallel.Enable);
end
if usePar
    localEnsureParpool(Cfg);
end

fprintf('\n========== GUV_VideoPipeline ==========');
fprintf('\nOutRoot : %s\n', Cfg.OutRoot);
fprintf('XY count: %d\n', numel(sidRun));
fprintf('Tasks   : %s\n', strjoin(string(Cfg.Video.Tasks), ','));
fprintf('Parallel: %d\n', usePar);
fprintf('======================================\n');

outFilesCell = cell(numel(sidRun),1);

if usePar
    parfor ii = 1:numel(sidRun)
        sid = sidRun(ii);
        outFilesCell{ii} = localRunOne(sid, sidAll, xyDirs, prefix, Cfg);
    end
else
    for ii = 1:numel(sidRun)
        sid = sidRun(ii);
        outFilesCell{ii} = localRunOne(sid, sidAll, xyDirs, prefix, Cfg);
    end
end

% 汇总输出文件列表
outFiles = vertcat(outFilesCell{:});

end

% =====================================================================
% Local helpers
% =====================================================================

function files = localRunOne(sid, sidAll, xyDirs, prefix, Cfg)
files = {};
idx = find(sidAll==sid, 1, 'first');
if isempty(idx)
    return;
end
seriesFolder = fullfile(Cfg.OutRoot, xyDirs(idx).name);

try
    files = guvVideo_exportSeries(seriesFolder, Cfg, sid, prefix);
catch ME
    warning('[%s%03d] Video export failed: %s', prefix, sid, ME.message);
end
end

function cfgPath = localFindConfigJson(OutputPath, thisDir)
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
    return;
end

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
