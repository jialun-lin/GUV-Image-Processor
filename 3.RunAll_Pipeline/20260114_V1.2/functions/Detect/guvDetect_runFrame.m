function [GUVData, fig] = guvDetect_runFrame(I, CType, minMajor_px, maxMajor_px, DetectOpts)
%GUVDETECT_RUNFRAME 单帧检测：输出“实心对象(innerMask)”以及强度(inner/mem/bg)
% -------------------------------------------------------------------------
% 输入：
%   I          : 单通道2D图像（uint16/uint8/single/double均可）
%   CType      : 'inner' 或 'mem'（仅影响mask构造方式；强度含义固定）
%   minMajor_px, maxMajor_px : 主轴长度过滤阈值（像素）
%   DetectOpts : 结构体，继承自 Cfg.Detect.Opts（可包含bin/inner/split/debug等）
%
% 输出（与旧版字段保持兼容）：
%   GUVData.centroids / majorAxisLength / Areas / filledAreas / Perimeters / bboxes
%   GUVData.subMasks            : 每个对象的局部实心mask（用于 inner 强度）
%   GUVData.memBandMasks        : 每个对象的局部环带mask（用于 mem 强度）
%   GUVData.meanIntensities     : meanIntensity_inner（在subMasks上测量）
%   GUVData.meanIntensities_mem : meanIntensity_mem  （在memBandMasks上测量）
%   GUVData.bgMeanIntensity     : 背景均值（标量）
%
% 你确认的核心规则：
%   - 对象集合永远用“实心 innerMask”定义（即GUV填充区域）
%   - meanIntensity_inner 永远表示“实心区域平均强度”
%   - meanIntensity_mem  永远表示“实心区域轮廓固定厚度环带平均强度”
%   - CType 仅用于从原图构造 innerMask/bgMask/memMask（语义差异见下）
%
% mask语义：
%   - oneMask：阈值后为1的二值mask（通用中间量，不输出或仅debug）
%   - CType='inner'：oneMask==innerMask（实心内水）
%   - CType='mem'  ：oneMask==memMask（膜）；zeroMask==~memMask，再拆出 innerMask/bgMask
% -------------------------------------------------------------------------

if nargin < 2 || isempty(CType), CType = 'inner'; end
if nargin < 5 || isempty(DetectOpts), DetectOpts = struct(); end

fig = [];
CType = lower(string(CType));
if CType ~= "inner" && CType ~= "mem"
    CType = "inner";
end

% -------- 1) 归一化 + 自适应阈值 → oneMask --------
binOpt = struct(); innerOpt = struct(); splitOpt = struct(); dbgOpt = struct();
if isfield(DetectOpts,'bin'),   binOpt = DetectOpts.bin;   end
if isfield(DetectOpts,'inner'), innerOpt = DetectOpts.inner; end
if isfield(DetectOpts,'split'), splitOpt = DetectOpts.split; end
if isfield(DetectOpts,'debug'), dbgOpt = DetectOpts.debug; end

I_raw = double(I);
[I_norm, oneMask] = guvDetect_binarizeAdaptive(I, binOpt);

% -------- 2) 按 CType 构造 innerMask/bgMask (memMask仅在mem通道有意义) --------
memMask = [];
switch CType
    case "inner"
        % 实心内水：oneMask就是innerMask
        innerMask = imfill(oneMask, 'holes');
        if isfield(innerOpt,'areaOpen') && innerOpt.areaOpen > 0
            innerMask = bwareaopen(innerMask, innerOpt.areaOpen);
        end
        bgMask = ~innerMask;

    otherwise % "mem"
        % 空心膜：oneMask就是memMask；zeroMask中包含 inner+bg
        memMask = oneMask;
        zeroMask = ~memMask;

        % flood-fill 抓外背景（从图像边界在zeroMask内扩张）
        bgMask = guvDetect_backgroundFloodFill(zeroMask, innerOpt);

        % 内水=zeroMask去掉bgMask
        innerMask = zeroMask & ~bgMask;

        % 可选：对 innerMask 做清理/分割
        if isfield(innerOpt,'areaOpen') && innerOpt.areaOpen > 0
            innerMask = bwareaopen(innerMask, innerOpt.areaOpen);
        end

        % 保持旧逻辑：若启用split（例如watershed），可在innerMask上进一步拆分
        if isfield(splitOpt,'doSplit') && splitOpt.doSplit
            innerMask = imfill(innerMask,'holes');
            if isfield(splitOpt,'openR') && splitOpt.openR > 0
                innerMask = imopen(innerMask, strel('disk', splitOpt.openR));
            end
            D = -bwdist(~innerMask);
            if isfield(splitOpt,'splitH') && splitOpt.splitH > 0
                D = imhmin(D, splitOpt.splitH);
            end
            Lw = watershed(D);
            innerMask(Lw==0) = 0;
            if isfield(innerOpt,'areaOpen') && innerOpt.areaOpen > 0
                innerMask = bwareaopen(innerMask, innerOpt.areaOpen);
            end
        end
end

% -------- 3) 背景均值（标量）--------
if any(bgMask(:))
    bgMean = mean(double(I_raw(bgMask)), 'omitnan');
else
    bgMean = mean(double(I_raw(:)), 'omitnan');
end
if isempty(bgMean) || isnan(bgMean), bgMean = 0; end

% -------- 4) 连通域 + 特征化：始终在 innerMask 上做 regionprops --------
CC = bwconncomp(innerMask, 8);
stats = regionprops(CC, I_raw, ...
    'Centroid','MajorAxisLength','Area','FilledArea','Orientation','Perimeter', ...
    'Image','BoundingBox','MeanIntensity');

% 组装GUVData（复用包内 buildDataStruct）
[GUVData, ~] = guvDetect_buildDataStruct(I_raw, size(I_norm), innerMask, stats, DetectOpts, true);

% 主轴过滤
if ~isempty(GUVData.majorAxisLength)
    keep = (GUVData.majorAxisLength >= minMajor_px) & (GUVData.majorAxisLength <= maxMajor_px);
else
    keep = false(0,1);
end
GUVData = localKeep(GUVData, keep);

% -------- 额外步骤：近邻去重/合并（仅对 CType==mem 生效） --------
% 说明：旧包中该步骤发生在 inner-mem 合并之后，用于把“非常靠近的重复候选”合并成一个。
%      在当前新逻辑里，我们只对 CType=mem 的通道执行（符合你的要求）。
if CType == "mem"
    if isfield(DetectOpts,'suppressClose') && isfield(DetectOpts.suppressClose,'enable') ...
            && DetectOpts.suppressClose.enable && isfield(DetectOpts.suppressClose,'dist_px') ...
            && DetectOpts.suppressClose.dist_px > 0
        try
            GUVData = guvDetect_suppressCloseGUVs(GUVData, DetectOpts.suppressClose.dist_px);
        catch ME
            warning('suppressClose failed: %s', ME.message);
        end
    end
end


% -------- 5) 环带mask + mem强度（由subMasks派生，不依赖mem通道）--------
if isfield(GUVData,'bboxes') && isfield(GUVData,'subMasks') && ~isempty(GUVData.subMasks)
    [bandMasks, memInt] = guvDetect_computeMemBandFromSubMasks(I_raw, GUVData.bboxes, GUVData.subMasks, DetectOpts);
    GUVData.memBandMasks = bandMasks;
    GUVData.meanIntensities_mem = memInt;
else
    GUVData.memBandMasks = {};
    GUVData.meanIntensities_mem = [];
end

% -------- 6) 挂载背景与可选mask（便于debug，不影响追踪/表格）--------
GUVData.bgMeanIntensity = bgMean;
GUVData.innerMask = innerMask;
if ~isempty(memMask)
    GUVData.memMask = memMask; % 仅mem通道有意义
end

% -------- 7) debug图（可选）--------
makeFig = false;
if isfield(dbgOpt,'makeFigure'), makeFig = logical(dbgOpt.makeFigure); end
if makeFig
    fig = figure('Color','w','Name','Detect Debug');
    tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
    nexttile; imshow(I_norm,[]); title('I_{norm}');
    nexttile; imshow(oneMask,[]); title('oneMask (阈值=1)');
    nexttile; imshow(innerMask,[]); title(sprintf('innerMask (CType=%s)', CType));
end

end

function S = localKeep(S, keep)
% 对所有“逐对象字段”执行同样的筛选，保证字段长度一致
if isempty(keep), return; end
fn = fieldnames(S);
n = numel(keep);
for i = 1:numel(fn)
    v = S.(fn{i});
    if isnumeric(v) && size(v,1)==n
        S.(fn{i}) = v(keep,:);
    elseif iscell(v) && numel(v)==n
        S.(fn{i}) = v(keep,:);
    end
end
end