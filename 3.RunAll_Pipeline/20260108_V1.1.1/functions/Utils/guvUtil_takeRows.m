function Sout = guvUtil_takeRows(Sin, idx)
%GUVUTIL_TAKEROWS 从“单帧对象结构体”中抽取指定行（对象子集）。
% -------------------------------------------------------------------------
% 在本项目中，单帧检测/融合结果通常是一个 struct（例如 GUVData），其字段形式大致有三类：
%   1) 按对象逐行存储的数值矩阵：centroids(n×2)、bboxes(n×4)、majorAxisLength(n×1) 等
%   2) 按对象逐元存储的 cell：subMasks{n×1}、boundaries{n×1}、memBandMasks{n×1} 等
%   3) 非逐对象字段（整图/元信息）：imageSize、I、innerMask、memMask 等
%
% 本函数只对 (1)(2) 这两类字段进行行抽取；(3) 类型字段原样拷贝。
%
% 输入：
%   Sin : struct，包含单帧对象结果
%   idx : 要保留的对象索引（行号），例如 [1 3 5]
% 输出：
%   Sout: struct，和 Sin 字段一致，但逐对象字段被按 idx 子集化

Sout = Sin;
n = guvUtil_countObjects(Sin);

if isempty(idx) || n==0
    Sout = localMakeEmptyLike(Sin, n, 0);
    return;
end

idx = idx(:);
idx = idx(idx>=1 & idx<=n);
if isempty(idx)
    Sout = localMakeEmptyLike(Sin, n, 0);
    return;
end

fn = fieldnames(Sin);
for i = 1:numel(fn)
    f = fn{i};
    v = Sin.(f);

    % --- 数值逐对象字段：size(v,1)==n ---
    if isnumeric(v) && ~isscalar(v) && size(v,1) == n
        Sout.(f) = v(idx, :);
        continue;
    end

    % --- 逻辑逐对象字段 ---
    if islogical(v) && ~isscalar(v) && size(v,1) == n
        Sout.(f) = v(idx, :);
        continue;
    end

    % --- cell逐对象字段：numel(v)==n ---
    if iscell(v) && numel(v) == n
        Sout.(f) = v(idx);
        continue;
    end

    % 其它字段（元信息/整图/标量）原样保留
end
end


function Sout = localMakeEmptyLike(Sin, nIn, nOut)
% 把逐对象字段长度置为 nOut（通常为0）
Sout = Sin;
fn = fieldnames(Sin);
for i = 1:numel(fn)
    f = fn{i};
    v = Sin.(f);
    if isnumeric(v) && ~isscalar(v) && size(v,1)==nIn
        Sout.(f) = v([],:);
        if nOut>0, Sout.(f)=nan(nOut, size(v,2)); end
    elseif islogical(v) && ~isscalar(v) && size(v,1)==nIn
        Sout.(f) = v([],:);
        if nOut>0, Sout.(f)=false(nOut, size(v,2)); end
    elseif iscell(v) && numel(v)==nIn
        Sout.(f) = cell(nOut,1);
    end
end
end
