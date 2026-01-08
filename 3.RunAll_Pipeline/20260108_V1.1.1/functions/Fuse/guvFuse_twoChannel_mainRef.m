function [GUVData, FuseLog] = guvFuse_twoChannel_mainRef(det1, det2, c1, c2, maxDist_px, opts)
%GUVFUSE_TWOCHANNEL_MAINREF 双通道单帧融合：同帧配对 + 选主ref（面积大者）。
% -------------------------------------------------------------------------
% 你确认的融合/测量规则（非常重要）：
%   1) 每个通道都会独立检测，得到该通道自己的“实心对象集合”（subMasks 等）。
%   2) 同一帧内，对两通道对象做配对（centroid距离门控，可选IoU二次确认）。
%   3) 若一对对象在两通道都存在：比较 imfill 后(或FilledArea)面积，面积更大的对象作为“主ref对象”。
%      - 主ref对象决定本帧输出对象的几何（subMasks/bboxes/centroids/majorAxis/...）
%   4) 后续所有通道强度（inner/mem/bg）都统一用“主ref对象”的 masks 来测量（在 Series 循环里完成）。
%
% 输入：
%   det1/det2  : 两通道单帧检测输出（struct），至少包含：
%                  centroids(n×2), bboxes(n×4), subMasks{n}, memBandMasks{n}(可空),
%                  filledAreas(n×1) 或 FilledAreas(n×1)
%   c1/c2      : 通道编号（用于写日志）
%   maxDist_px : 配对距离阈值（像素）
%   opts       : 结构体，可选字段：
%                  .UseIoU (true/false)
%                  .MinIoU (0~1)
%
% 输出：
%   GUVData : 融合后的单帧对象结果（几何来自主ref对象）
%   FuseLog : 结构体，记录配对/来源统计（用于debug）

if nargin < 6, opts = struct(); end
opts = localSetDefault(opts, 'UseIoU', false);
opts = localSetDefault(opts, 'MinIoU', 0.0);

n1 = guvUtil_countObjects(det1);
n2 = guvUtil_countObjects(det2);

% --------- 取 filled area（尽量兼容旧字段命名）---------
a1 = localGetFilledAreas(det1, n1);
a2 = localGetFilledAreas(det2, n2);

% --------- 计算候选配对（距离门控）---------
pairs = zeros(0,3); % [i1 i2 dist]
if n1>0 && n2>0
    D = pdist2(det1.centroids, det2.centroids);
    [ii,jj] = find(D <= maxDist_px);
    if ~isempty(ii)
        dd = D(sub2ind(size(D), ii, jj));
        pairs = [ii(:), jj(:), dd(:)];
        pairs = sortrows(pairs, 3); % 按距离从小到大
    end
end

% --------- 贪心一对一匹配（足够稳定，且易debug）---------
m1 = false(n1,1);
m2 = false(n2,1);
match = zeros(0,2); % [i1 i2]
for k = 1:size(pairs,1)
    i = pairs(k,1); j = pairs(k,2);
    if m1(i) || m2(j), continue; end

    if opts.UseIoU && opts.MinIoU > 0
        iou = guvUtil_iouFromBBoxSubMask(det1.bboxes(i,:), det1.subMasks{i}, det2.bboxes(j,:), det2.subMasks{j});
        if iou < opts.MinIoU
            continue;
        end
    end

    m1(i) = true; m2(j) = true;
    match(end+1,:) = [i j]; %#ok<AGROW>
end

only1 = find(~m1);
only2 = find(~m2);

% --------- 为每个融合对象选择“主ref来源通道”---------
refFrom = zeros(size(match,1) + numel(only1) + numel(only2), 1); % 1=det1,2=det2
idxInCh = zeros(size(refFrom));   % 在对应通道det里的索引

srcIdxC1 = zeros(size(refFrom));
srcIdxC2 = zeros(size(refFrom));

k = 0;

% (A) matched pairs
for p = 1:size(match,1)
    i = match(p,1); j = match(p,2);
    k = k + 1;
    srcIdxC1(k) = i;
    srcIdxC2(k) = j;

    if a1(i) >= a2(j)
        refFrom(k) = 1; idxInCh(k) = i;
    else
        refFrom(k) = 2; idxInCh(k) = j;
    end
end

% (B) only in ch1
for t = 1:numel(only1)
    i = only1(t);
    k = k + 1;
    srcIdxC1(k) = i;
    srcIdxC2(k) = 0;
    refFrom(k) = 1; idxInCh(k) = i;
end

% (C) only in ch2
for t = 1:numel(only2)
    j = only2(t);
    k = k + 1;
    srcIdxC1(k) = 0;
    srcIdxC2(k) = j;
    refFrom(k) = 2; idxInCh(k) = j;
end

% --------- 组装输出：几何字段直接取主ref对象子集并“拼接”---------
idxFrom1 = idxInCh(refFrom==1);
idxFrom2 = idxInCh(refFrom==2);

part1 = localSelectCore(det1, idxFrom1);
part2 = localSelectCore(det2, idxFrom2);
GUVData = localConcatCore(part1, part2);

% --------- 写入映射信息（用于debug/追踪后回溯）---------
n = guvUtil_countObjects(GUVData);
GUVData.refFromC = nan(n,1);
GUVData.(['srcIdx_C' sprintf('%02d',c1)]) = nan(n,1);
GUVData.(['srcIdx_C' sprintf('%02d',c2)]) = nan(n,1);

% 注意：localConcatCore 的顺序是 [part1对象; part2对象]，
% 我们需要把 refFrom/映射索引同步到对应行。
% 对应关系：
%   - 前 numel(idxFrom1) 行：来自 det1
%   - 后 numel(idxFrom2) 行：来自 det2
nA = numel(idxFrom1);
nB = numel(idxFrom2);

% 对于来自 det1 的行：refFromC = c1
GUVData.refFromC(1:nA) = c1;
GUVData.(['srcIdx_C' sprintf('%02d',c1)])(1:nA) = idxFrom1(:);

% 对于来自 det2 的行：refFromC = c2
GUVData.refFromC(nA+(1:nB)) = c2;
GUVData.(['srcIdx_C' sprintf('%02d',c2)])(nA+(1:nB)) = idxFrom2(:);

% 对 matched 的情况：我们希望保留两边的来源索引。这里用 srcIdxC1/srcIdxC2 的整体顺序。
% 为了简化（并避免反向查找错误），我们把“融合顺序”也输出到日志里，在 debug 时对应即可。

FuseLog = struct();
FuseLog.c1 = c1; FuseLog.c2 = c2;
FuseLog.n1 = n1; FuseLog.n2 = n2;
FuseLog.nMatched = size(match,1);
FuseLog.nOnly1 = numel(only1);
FuseLog.nOnly2 = numel(only2);
FuseLog.maxDist_px = maxDist_px;
FuseLog.refFrom = refFrom;    % 1/2 表示主ref来自哪个det
FuseLog.idxInCh = idxInCh;    % 主ref在该det里的索引
FuseLog.srcIdxC1 = srcIdxC1;  % 每个融合对象在通道c1的索引（0=不存在）
FuseLog.srcIdxC2 = srcIdxC2;  % 每个融合对象在通道c2的索引（0=不存在）

end


% ======================= 内部小工具 =======================
function a = localGetFilledAreas(det, n)
a = nan(n,1);
if n==0, return; end
if isfield(det,'filledAreas') && ~isempty(det.filledAreas)
    a = det.filledAreas(:); return;
end
if isfield(det,'FilledAreas') && ~isempty(det.FilledAreas)
    a = det.FilledAreas(:); return;
end
% 兜底：用 Areas
if isfield(det,'Areas') && ~isempty(det.Areas)
    a = det.Areas(:); return;
end
end


function S2 = localSelectCore(S, idx)
% 只保留“逐对象字段”，丢弃整图 mask（innerMask/memMask）以避免融合语义混乱
S2 = S;
if ~isfield(S,'centroids') || isempty(idx)
    S2 = guvUtil_takeRows(S, []);
    return;
end
S2 = guvUtil_takeRows(S, idx);

% 移除可能为整图的字段（避免误用）
rmList = {'innerMask','memMask','I','imageSize'};
for k = 1:numel(rmList)
    if isfield(S2, rmList{k})
        S2.(rmList{k}) = [];
    end
end
end


function G = localConcatCore(A, B)
% 把两个“核心对象结构体”按对象维度拼接。
% 注意：这里只对逐对象字段拼接；非逐对象字段忽略（后续在Series循环里统一补 imageSize/I 等）
nA = guvUtil_countObjects(A);
nB = guvUtil_countObjects(B);

% union fields
fn = unique([fieldnames(A); fieldnames(B)]);
G = struct();
for i = 1:numel(fn)
    f = fn{i};

    va = [];
    vb = [];
    hasA = isfield(A,f);
    hasB = isfield(B,f);
    if hasA, va = A.(f); end
    if hasB, vb = B.(f); end

    if hasA && isnumeric(va) && ~isscalar(va) && size(va,1)==nA
        % numeric per-object
        if ~hasB
            vb = nan(nB, size(va,2));
        elseif isnumeric(vb) && ~isscalar(vb) && size(vb,1)==nB
            % ok
        else
            vb = nan(nB, size(va,2));
        end
        G.(f) = [va; vb];
        continue;
    end

    if hasB && isnumeric(vb) && ~isscalar(vb) && size(vb,1)==nB
        if ~hasA
            va = nan(nA, size(vb,2));
        elseif isnumeric(va) && ~isscalar(va) && size(va,1)==nA
        else
            va = nan(nA, size(vb,2));
        end
        G.(f) = [va; vb];
        continue;
    end

    if hasA && iscell(va) && numel(va)==nA
        if ~hasB
            vb = cell(nB,1);
        elseif iscell(vb) && numel(vb)==nB
        else
            vb = cell(nB,1);
        end
        G.(f) = [va; vb];
        continue;
    end

    if hasB && iscell(vb) && numel(vb)==nB
        if ~hasA
            va = cell(nA,1);
        elseif iscell(va) && numel(va)==nA
        else
            va = cell(nA,1);
        end
        G.(f) = [va; vb];
        continue;
    end

    % 默认：取A的字段（或B）
    if hasA
        G.(f) = va;
    else
        G.(f) = vb;
    end
end
end


function s = localSetDefault(s, name, value)
if ~isfield(s, name) || isempty(s.(name))
    s.(name) = value;
end
end
