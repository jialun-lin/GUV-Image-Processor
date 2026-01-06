function fig = guvDebug_makeFrameFigureFuse(Icell, CList, CNames, detC, GUVData, FuseLog, Cfg)
%GUVDEBUG_MAKEFRAMEFIGUREFUSE 生成逐帧调试图（双通道 2×2 面板 + mem debug）。
% =========================================================================
% 你要求的显示内容（默认双通道）：
%   左上：Ref 通道原图（显示用归一化/轻度平滑）
%   右上：Other 通道原图
%   左下：Ref 通道检测结果（bbox+编号）+ 主ref对象 subMask/memBand 轮廓
%   右下：Other 通道检测结果（bbox+编号）+ 同一套主ref subMask/memBand 轮廓
%
% mem debug：
%   - subMask 轮廓（绿色）
%   - memBand 轮廓（红色）
%   - 若某通道为 CType='mem' 且 detC{cc} 含 memMask，则可选叠加 memMask 轮廓（青色）
%
% 输入：
%   Icell  : {nC×1} 每通道原图（二维）
%   CList  : [1×nC] 通道编号
%   CNames : {1×nC} 通道名称（用于标题）
%   detC   : {nC×1} 每通道独立检测输出（含 bboxes/centroids/memMask等；用于画“本通道框选结果”）
%   GUVData: 融合后（主ref）的对象集合（含 subMasks/memBandMasks/bboxes/centroids）
%   FuseLog: 融合统计（n1/n2/nMatched/nOnly1/nOnly2）
%   Cfg    : 配置（至少含 Read.RefC / Read.OtherC / Debug.*）

if nargin < 7, Cfg = struct(); end
if nargin < 6, FuseLog = struct(); end
if nargin < 5, GUVData = struct(); end
if nargin < 4, detC = []; end

nC = numel(Icell);
if nC == 0
    fig = figure('Visible','off'); return;
end

% ---- Debug 选项 ----
showMemBand = true;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'ShowMemBand')
    showMemBand = logical(Cfg.Debug.ShowMemBand);
end
showMemMask = false;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'ShowMemMask')
    showMemMask = logical(Cfg.Debug.ShowMemMask);
end

% ---- ref/other 索引 ----
refIdx = 1;
if isfield(Cfg,'Read') && isfield(Cfg.Read,'RefC')
    ii = find(CList == Cfg.Read.RefC, 1, 'first');
    if ~isempty(ii), refIdx = ii; end
end
othIdx = min(2,nC);
if isfield(Cfg,'Read') && isfield(Cfg.Read,'OtherC') && ~isempty(Cfg.Read.OtherC)
    jj = find(CList == Cfg.Read.OtherC, 1, 'first');
    if ~isempty(jj), othIdx = jj; end
elseif nC >= 2
    % 默认：选择第一个非ref通道
    cand = 1:nC; cand(refIdx) = [];
    if ~isempty(cand), othIdx = cand(1); end
else
    othIdx = refIdx;
end

% ---- 构造 2×2 画布 ----
fig = figure('Color','w','Name','GUV Debug (Fuse 2x2)','Visible','off');
tiledlayout(fig, 2, 2, 'Padding','compact', 'TileSpacing','compact');

% ---- 顶部标题：融合统计 ----
txt = '';
if isstruct(FuseLog)
    if isfield(FuseLog,'n1') && isfield(FuseLog,'n2')
        txt = sprintf('n1=%d, n2=%d, matched=%d, only1=%d, only2=%d', ...
            FuseLog.n1, FuseLog.n2, FuseLog.nMatched, FuseLog.nOnly1, FuseLog.nOnly2);
    elseif isfield(FuseLog,'mode')
        txt = sprintf('FuseMode: %s', string(FuseLog.mode));
    end
end
seriesPrefix = 'XY';
if isfield(Cfg,'SeriesPrefix'), seriesPrefix = Cfg.SeriesPrefix; end
sgtitle(sprintf('%s | %s', seriesPrefix, txt), 'Interpreter','none');

% ========== 左上：Ref 原图 ==========
nexttile;
imshow(localShowImage(Icell{refIdx}), []);
title(sprintf('C%02d %s (Ref raw)', CList(refIdx), CNames{refIdx}), 'Interpreter','none');

% ========== 右上：Other 原图 ==========
nexttile;
imshow(localShowImage(Icell{othIdx}), []);
title(sprintf('C%02d %s (Other raw)', CList(othIdx), CNames{othIdx}), 'Interpreter','none');

% ========== 左下：Ref 框选 + 主ref masks ==========
nexttile;
imshow(localShowImage(Icell{refIdx}), []); hold on;
localDrawBoxes(detC, refIdx);
localDrawMainRefMasks(GUVData, showMemBand);
if showMemMask
    localDrawFullMask(detC, refIdx, 'memMask', 'c');
end
title(sprintf('Ref boxes + mainRef masks'), 'Interpreter','none');
hold off;

% ========== 右下：Other 框选 + 主ref masks ==========
nexttile;
imshow(localShowImage(Icell{othIdx}), []); hold on;
localDrawBoxes(detC, othIdx);
localDrawMainRefMasks(GUVData, showMemBand);
if showMemMask
    localDrawFullMask(detC, othIdx, 'memMask', 'c');
end
title(sprintf('Other boxes + mainRef masks'), 'Interpreter','none');
hold off;

end

% -------------------------------------------------------------------------
function Ishow = localShowImage(I)
% 仅用于显示：归一化 + 轻度平滑（不影响算法输出）
try
    Ishow = mat2gray(I);
catch
    Ishow = double(I);
    Ishow = Ishow ./ max(Ishow(:) + eps);
end
end

function localDrawBoxes(detC, idx)
% 在当前 axes 上画该通道的 bbox + 质心编号
if isempty(detC) || numel(detC) < idx || isempty(detC{idx}) || ~isstruct(detC{idx})
    return;
end
det = detC{idx};
if ~isfield(det,'bboxes') || isempty(det.bboxes)
    return;
end
bb = det.bboxes;
for k = 1:size(bb,1)
    rectangle('Position', bb(k,:), 'EdgeColor','y', 'LineWidth', 1);
end
if isfield(det,'centroids') && ~isempty(det.centroids)
    cxy = det.centroids;
    for k = 1:size(cxy,1)
        text(cxy(k,1)+2, cxy(k,2), sprintf('%d', k), 'Color','y', 'FontSize',8, 'FontWeight','bold');
    end
end
end

function localDrawMainRefMasks(G, showMemBand)
% 绘制融合后的主ref对象轮廓：subMask(绿) + memBand(红，可选)
if isempty(G) || ~isstruct(G)
    return;
end
if ~isfield(G,'bboxes') || ~isfield(G,'subMasks') || isempty(G.subMasks)
    return;
end

% subMask（绿）
localDrawLocalMaskBoundaries(G.subMasks, G.bboxes, 'g', 1.0);

% memBand（红）
if showMemBand && isfield(G,'memBandMasks') && ~isempty(G.memBandMasks)
    localDrawLocalMaskBoundaries(G.memBandMasks, G.bboxes, 'r', 0.9);
end
end

function localDrawLocalMaskBoundaries(maskList, bboxes, colorChar, lw)
% maskList{k} 是 ROI 内局部 mask，需按 bboxes 偏移到全图坐标
if isempty(maskList) || isempty(bboxes)
    return;
end
n = min(numel(maskList), size(bboxes,1));
for k = 1:n
    mk = maskList{k};
    if isempty(mk) || ~any(mk(:)), continue; end
    bb = bboxes(k,:);  % [x y w h] (1-based)
    try
        B = bwboundaries(mk);
    catch
        continue;
    end
    for b = 1:numel(B)
        xy = B{b};
        if isempty(xy), continue; end
        % xy(:,1)=row(y), xy(:,2)=col(x)
        x = xy(:,2) + bb(1) - 1;
        y = xy(:,1) + bb(2) - 1;
        plot(x, y, '-', 'Color', colorChar, 'LineWidth', lw);
    end
end
end

function localDrawFullMask(detC, idx, fieldName, colorChar)
% 绘制全图 mask 的轮廓（例如 memMask）
if isempty(detC) || numel(detC) < idx || isempty(detC{idx}) || ~isstruct(detC{idx})
    return;
end
det = detC{idx};
if ~isfield(det, fieldName) || isempty(det.(fieldName))
    return;
end
mk = det.(fieldName);
if ~any(mk(:)), return; end
try
    B = bwboundaries(mk);
catch
    return;
end
for b = 1:numel(B)
    xy = B{b};
    if isempty(xy), continue; end
    x = xy(:,2);
    y = xy(:,1);
    plot(x, y, '-', 'Color', colorChar, 'LineWidth', 0.5);
end
end
