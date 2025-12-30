function bgMask = guvDetect_backgroundFloodFill(zeroMask, innerOpt)
%GUVDETECT_BACKGROUNDFLOODFILL 在 zeroMask(背景+内水=1)上从顶部种子洪泛，提取背景。
% 逻辑与 detectGUVRegions 一致：
%   - 在 seedRow 行均匀撒 nSeeds 个 seed
%   - 取 flood-fill 面积最大的那个 region 作为背景
%   - 若 seed 全失败：退化为取 zeroMask 的最大连通域

if nargin < 2, innerOpt = struct(); end
innerOpt = guvUtil_setDefault(innerOpt,'seedRow',2);
innerOpt = guvUtil_setDefault(innerOpt,'nSeeds',10);

[H, W] = size(zeroMask);

bgMask = false(size(zeroMask));
ySeed = innerOpt.seedRow;
xs = round(linspace(1, W, innerOpt.nSeeds));

bestArea = 0;
for k = 1:numel(xs)
    x = xs(k);
    if ySeed>=1 && ySeed<=H && zeroMask(ySeed, x)
        region = guvDetect_floodfillBinary(zeroMask, ySeed, x);
        area = nnz(region);
        if area > bestArea
            bestArea = area;
            bgMask = region;
        end
    end
end

if bestArea == 0
    % 兜底：取最大连通域作为背景
    CC0 = bwconncomp(zeroMask, 8);
    if CC0.NumObjects > 0
        areas0 = cellfun(@numel, CC0.PixelIdxList);
        [~, idxBg] = max(areas0);
        bgMask = false(size(zeroMask));
        bgMask(CC0.PixelIdxList{idxBg}) = true;
    end
end
end
