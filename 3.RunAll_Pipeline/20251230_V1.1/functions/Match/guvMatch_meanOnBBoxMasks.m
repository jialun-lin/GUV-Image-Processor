function m = guvMatch_meanOnBBoxMasks(I_norm, bboxes, maskList)
%GUVMATCH_MEANONBBOXMASKS 在 bbox 局部mask上计算均值（逐对象）
% -------------------------------------------------------------------------
% 为什么不直接用全图mask？
%   - subMasks/memBandMasks 在本包中通常是“bbox裁剪后的局部mask”，存储更省空间
%   - 因此取值时需要把 bbox 对应的图像块裁剪出来，再用局部mask索引
%
% 输入：
%   I_norm   : 归一化后的图像（double/ single），与bbox对应原图坐标
%   bboxes   : [N×4]，regionprops BoundingBox，格式 [x y w h]（x,y从0开始的像素坐标）
%   maskList : N×1 cell，每个元素为局部mask（逻辑矩阵）
% 输出：
%   m        : N×1，均值（mask为空则为NaN）
% -------------------------------------------------------------------------

n = 0;
if ~isempty(bboxes)
    n = size(bboxes,1);
else
    n = numel(maskList);
end
m = nan(n,1);
if n==0 || isempty(I_norm), return; end

[H,W] = size(I_norm);

for k = 1:n
    if k>numel(maskList) || isempty(maskList{k}) || k>size(bboxes,1)
        continue;
    end
    bb = bboxes(k,:);
    % regionprops BoundingBox：x/y 是从0开始的浮点坐标
    x1 = max(1, floor(bb(1))+1);
    y1 = max(1, floor(bb(2))+1);
    x2 = min(W, floor(bb(1)+bb(3)));
    y2 = min(H, floor(bb(2)+bb(4)));
    if x2 < x1 || y2 < y1, continue; end

    crop = I_norm(y1:y2, x1:x2);
    mk = logical(maskList{k});

    % 尺寸对齐（某些情况下bbox裁剪会差1像素）
    hh = min(size(crop,1), size(mk,1));
    ww = min(size(crop,2), size(mk,2));
    crop = crop(1:hh,1:ww);
    mk = mk(1:hh,1:ww);

    if ~any(mk(:)), continue; end
    v = crop(mk);
    m(k) = mean(double(v), 'omitnan');
end
end
