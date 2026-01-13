function iou = guvUtil_iouFromBBoxSubMask(bb1, m1, bb2, m2)
%GUVUTIL_IOUFROMBBOXSUBMASK 由 bbox([x y w h]) 与局部mask(Image)计算 IoU。
% bbox: [x y w h] (x/y 0-based-ish in regionprops style)
% m1/m2: logical mask in bbox local coordinates

iou = 0;
if isempty(bb1) || isempty(bb2) || isempty(m1) || isempty(m2)
    return;
end

m1 = logical(m1);
m2 = logical(m2);

% 计算两 bbox 在全图中的整数包围盒 (1-based像素坐标)
% regionprops bbox: x,y 以 0.5/1 为基准的浮点；这里采用 floor/ceil 保守包含
x11 = floor(bb1(1)) + 1;
y11 = floor(bb1(2)) + 1;
x12 = x11 + size(m1,2) - 1;
y12 = y11 + size(m1,1) - 1;

x21 = floor(bb2(1)) + 1;
y21 = floor(bb2(2)) + 1;
x22 = x21 + size(m2,2) - 1;
y22 = y21 + size(m2,1) - 1;

% 重叠区域
xi1 = max(x11, x21);
yi1 = max(y11, y21);
xi2 = min(x12, x22);
yi2 = min(y12, y22);

if xi2 < xi1 || yi2 < yi1
    return;
end

% 将重叠区域映射回各自局部 mask 坐标
m1x1 = xi1 - x11 + 1; m1x2 = xi2 - x11 + 1;
m1y1 = yi1 - y11 + 1; m1y2 = yi2 - y11 + 1;

m2x1 = xi1 - x21 + 1; m2x2 = xi2 - x21 + 1;
m2y1 = yi1 - y21 + 1; m2y2 = yi2 - y21 + 1;

A = m1(m1y1:m1y2, m1x1:m1x2);
B = m2(m2y1:m2y2, m2x1:m2x2);

inter = nnz(A & B);
uni   = nnz(A | B) + (nnz(m1) - nnz(A)) + (nnz(m2) - nnz(B));

% 上式把非重叠部分也加到了 union：union = |A∪B| + |m1\A| + |m2\B|
if uni > 0
    iou = inter / uni;
end
end
