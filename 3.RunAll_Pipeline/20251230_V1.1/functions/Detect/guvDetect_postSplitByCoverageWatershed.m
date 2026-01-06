function GUVDataOut = guvDetect_postSplitByCoverageWatershed(I, GUVDataIn, PrevGUVData, Cfg, DetectOpts)
%POSTSPLITBYCOVERAGEWATERSHED
% 后处理可选步骤：基于“面积覆盖率 Cover(t)”对单个对象做自适应分水岭细分。
%
% 思路（按你的要求）：
%   1) 先沿用现有 FF/阈值检测的输出（GUVDataIn），不改变主检测逻辑。
%   2) 用上一帧 PrevGUVData 中与当前对象最相似者（最大 IoU）作为参照，计算
%        Cover = min(A_t, A_prev) / max(A_t, A_prev)
%   3) 若 Cover < Tau：说明本帧对象面积突变，疑似粘连/漏检 → 用更小 h（更易分割）
%      若 Cover >= Tau：用更大 h（更保守）
%   4) 在该对象 ROI 内做分水岭；分割后对每个子区域重新计算 centroid/major/area/meanIntensity 等。
%
% 输入：
%   I           : 当前帧原图（uint16/float均可）
%   GUVDataIn   : detectGUVRegions 输出（需含 bboxes, subMasks, areas/filledAreas）
%   PrevGUVData : 上一帧 detect 输出（可为空）
%   Cfg         : 配置（Cfg.Post.Watershed.*）
%   DetectOpts  : 检测参数（用于判断 mem/inner 的 mask 类型等，可选）
%
% 输出：
%   GUVDataOut  : 细分后的 GUVData（字段尽量保持原结构）

if nargin < 5
    DetectOpts = struct();
end

GUVDataOut = GUVDataIn;

if ~isfield(Cfg,'Post') || ~isfield(Cfg.Post,'Watershed') || ~Cfg.Post.Watershed.Enable
    return;
end

WS = Cfg.Post.Watershed;

% ---- 参数默认值（即使用户没填也不报错） ----
if ~isfield(WS,'Tau'),          WS.Tau = 0.7; end
if ~isfield(WS,'hLow'),         WS.hLow = 1.0; end
if ~isfield(WS,'hHigh'),        WS.hHigh = 3.0; end
if ~isfield(WS,'MarginPx'),     WS.MarginPx = 6; end
if ~isfield(WS,'MinAreaPx'),    WS.MinAreaPx = 30; end
if ~isfield(WS,'MaxChild'),     WS.MaxChild = 6; end
if ~isfield(WS,'SigmaD'),       WS.SigmaD = 1.0; end

% ---- 必需字段检查 ----
if ~isfield(GUVDataIn,'bboxes') || ~isfield(GUVDataIn,'subMasks')
    % 没有实例mask，无法在 ROI 做分水岭
    return;
end

bboxes = GUVDataIn.bboxes;
subMasks = GUVDataIn.subMasks;

if isempty(bboxes) || isempty(subMasks)
    return;
end

% 当前帧 area（优先 filledAreas 其次 Areas）
Acur = getFieldOr(GUVDataIn, 'filledAreas', []);
if isempty(Acur)
    Acur = getFieldOr(GUVDataIn, 'Areas', []);
end

% 上一帧准备
hasPrev = ~isempty(PrevGUVData) && isfield(PrevGUVData,'bboxes') && isfield(PrevGUVData,'subMasks');
if hasPrev
    bbPrev = PrevGUVData.bboxes;
    mPrev  = PrevGUVData.subMasks;
    Aprev  = getFieldOr(PrevGUVData, 'filledAreas', []);
    if isempty(Aprev)
        Aprev = getFieldOr(PrevGUVData, 'Areas', []);
    end
else
    bbPrev = zeros(0,4);
    mPrev = {};
    Aprev = zeros(0,1);
end

% 归一化强度图（与 detectGUVRegions 保持一致：MeanIntensity 在 mat2gray 后的 [0,1] 强度上计算）
I2 = mat2gray(I);

H = size(I2,1); W = size(I2,2);

% ---- 构建输出列表（逐对象可能拆分成多个子对象） ----
new_centroids = [];
new_major = [];
new_areas = [];
new_filled = [];
new_perim = [];
new_meanI = [];
new_bboxes = zeros(0,4);
new_subMasks = {};
new_boundaries = {};

% 继承其它字段（会在末尾按索引填/留空）
keepFields = fieldnames(GUVDataIn);

for i = 1:size(bboxes,1)
    bb = bboxes(i,:);
    if i > numel(subMasks) || isempty(subMasks{i})
        continue;
    end
    mask0 = logical(subMasks{i});

    % 计算 Cover（用上一帧最大 IoU 的对象做参照）
    cover = 1.0;
    if hasPrev && ~isempty(bbPrev)
        [bestIoU, bestIdx] = bestIoUWithPrev(bb, mask0, bbPrev, mPrev);
        if bestIoU > 0 && bestIdx >= 1 && bestIdx <= numel(Aprev) && i <= numel(Acur)
            a1 = Acur(i);
            a0 = Aprev(bestIdx);
            if ~isempty(a1) && ~isempty(a0) && a1>0 && a0>0
                cover = min(a1,a0) / max(a1,a0);
            end
        end
    end

    % 选择 h
    if cover < WS.Tau
        h = WS.hLow;
    else
        h = WS.hHigh;
    end

    % ROI（在 bbox 基础上扩张）
    [x1,y1,x2,y2] = bboxExpandClamp(bb, WS.MarginPx, H, W);
    roiMask = false(y2-y1+1, x2-x1+1);

    % 将 mask0 放入 roiMask
    % mask0 尺寸应与 bbox 的 w/h 对应
    % bbox: [x y w h]，regionprops 的 w/h 可能是浮点，需四舍五入对齐
    bx = round(bb(1)); by = round(bb(2)); bw = round(bb(3)); bh = round(bb(4));
    if bw<=0 || bh<=0
        continue;
    end
    % 计算 mask0 在全图的左上角
    gx1 = bx; gy1 = by;
    gx2 = bx + bw - 1; gy2 = by + bh - 1;

    % 与 ROI 的交集
    ix1 = max(gx1, x1); iy1 = max(gy1, y1);
    ix2 = min(gx2, x2); iy2 = min(gy2, y2);
    if ix1>ix2 || iy1>iy2
        continue;
    end

    % mask0 内部对应坐标
    mx1 = ix1 - gx1 + 1; my1 = iy1 - gy1 + 1;
    mx2 = ix2 - gx1 + 1; my2 = iy2 - gy1 + 1;

    % roiMask 内部对应坐标
    rx1 = ix1 - x1 + 1; ry1 = iy1 - y1 + 1;
    rx2 = ix2 - x1 + 1; ry2 = iy2 - y1 + 1;

    tmp = false(size(roiMask));
    tmp(ry1:ry2, rx1:rx2) = mask0(my1:my2, mx1:mx2);
    roiMask = tmp;

    % 对膜环形 mask：填洞更符合“一个对象”的占据区域（也让 IoU/面积更稳定）
    if isfield(Cfg.Track.Opts,'IoUUseFilledMask') && Cfg.Track.Opts.IoUUseFilledMask
        roiMask = imfill(roiMask, 'holes');
    end

    % 若 roiMask 太小/空，则跳过
    if nnz(roiMask) < WS.MinAreaPx
        % 不分割，直接保留原对象（用原数据）
        [new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries] = ...
            appendOriginal(i, GUVDataIn, new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries);
        continue;
    end

    % ---- 分水岭分割（仅在 ROI 内对该对象进行） ----
    % 距离变换：对象内部到边界的距离，中心更大
    D = bwdist(~roiMask);
    if WS.SigmaD > 0
        D = imgaussfilt(D, WS.SigmaD);
    end
    % h 控制“最大值抑制”：h 越大，保留的峰越少（更保守）
    D2 = imhmax(D, h);
    % watershed 对 -D2
    L = watershed(-D2);
    seg = roiMask;
    seg(L==0) = 0; % 分水岭脊线置0 -> 形成分割

    CC = bwconncomp(seg);
    if CC.NumObjects <= 1
        % 没分开：保留原对象
        [new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries] = ...
            appendOriginal(i, GUVDataIn, new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries);
        continue;
    end

    % 过滤太小的子块
    stats = regionprops(CC, I2(y1:y2, x1:x2), 'Area','Centroid','MajorAxisLength','Perimeter','MeanIntensity','BoundingBox','Image');
    areasChild = [stats.Area]';
    keep = find(areasChild >= WS.MinAreaPx);

    if isempty(keep)
        [new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries] = ...
            appendOriginal(i, GUVDataIn, new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries);
        continue;
    end

    % 限制子块数量，避免过分割爆炸
    if numel(keep) > WS.MaxChild
        [~,ord] = sort(areasChild(keep),'descend');
        keep = keep(ord(1:WS.MaxChild));
    end

    for kk = 1:numel(keep)
        s = stats(keep(kk));
        % 全图坐标
        c = s.Centroid + [x1-1, y1-1];
        new_centroids(end+1,:) = c; %#ok<AGROW>
        new_major(end+1,1) = s.MajorAxisLength; %#ok<AGROW>
        new_areas(end+1,1) = s.Area; %#ok<AGROW>
        new_filled(end+1,1) = s.Area; %#ok<AGROW> % 这里 filled 先等于 area；如需可用 imfill 后再算
        new_perim(end+1,1) = s.Perimeter; %#ok<AGROW>
        new_meanI(end+1,1) = s.MeanIntensity; %#ok<AGROW>

        bbLocal = s.BoundingBox; % ROI内 bbox
        bbGlobal = bbLocal + [x1-1, y1-1, 0, 0];
        new_bboxes(end+1,:) = bbGlobal; %#ok<AGROW>
        new_subMasks{end+1,1} = logical(s.Image); %#ok<AGROW>

        % boundary（取最长外轮廓）
        sub = logical(s.Image);
        sub = imfill(sub,'holes');
        B = bwboundaries(sub, 8, 'noholes');
        if isempty(B)
            new_boundaries{end+1,1} = [];
        else
            [~,idmax] = max(cellfun(@(x)size(x,1), B));
            b = B{idmax};
            % b: [row col] -> [x y]
            x = b(:,2) + bbGlobal(1) - 1;
            y = b(:,1) + bbGlobal(2) - 1;
            new_boundaries{end+1,1} = [x y];
        end
    end
end

% ---- 写回 GUVDataOut（保持字段名一致） ----
GUVDataOut = struct();
GUVDataOut.centroids = new_centroids;
GUVDataOut.majorAxisLength = new_major;
GUVDataOut.Areas = new_areas;
GUVDataOut.filledAreas = new_filled;
GUVDataOut.Perimeters = new_perim;
GUVDataOut.meanIntensities = new_meanI;
GUVDataOut.bboxes = new_bboxes;
GUVDataOut.subMasks = new_subMasks;
GUVDataOut.boundaries = new_boundaries;

% ---- 继承/补充：背景强度（每帧标量，分割不会改变它） ----
if isfield(GUVDataIn,'bgMeanIntensity')
    GUVDataOut.bgMeanIntensity = GUVDataIn.bgMeanIntensity;
end

% ---- 重新计算：膜 band mask + 膜平均强度（因分割会改变实例 mask，必须重算） ----
% 参数：与 detectGUVRegions 的 Cfg.Detect.Opts.mem.* 一致
smoothR = 2;
thickR  = 3;
if isfield(Cfg,'Detect') && isfield(Cfg.Detect,'Opts') && isfield(Cfg.Detect.Opts,'mem')
    if isfield(Cfg.Detect.Opts.mem,'smoothR'), smoothR = Cfg.Detect.Opts.mem.smoothR; end
    if isfield(Cfg.Detect.Opts.mem,'thickR'),  thickR  = Cfg.Detect.Opts.mem.thickR;  end
end

nObj = size(new_bboxes,1);
memBandMasks = cell(nObj,1);
memIntensity = nan(nObj,1);

if nObj>0 && ~isempty(I2)
    [H2,W2] = size(I2);
    seSmooth = strel('disk', max(0,round(smoothR)), 0);
    seOut    = strel('disk', max(1,round(thickR)), 0);
    seIn     = strel('disk', max(1,round(thickR)-1), 0);

    for kk = 1:nObj
        if kk>numel(new_subMasks) || isempty(new_subMasks{kk})
            memBandMasks{kk} = [];
            continue;
        end
        m = logical(new_subMasks{kk});
        m = imfill(m,'holes');
        if smoothR>0
            m = imclose(m, seSmooth);
            m = imopen(m,  seSmooth);
            m = imfill(m,'holes');
        end
        outer = imdilate(m, seOut);
        inner = imerode(m, seIn);
        band = outer & ~inner;
        memBandMasks{kk} = band;

        % 用 bbox 在 I2 上裁剪，并在 band 上取均值（与 detectGUVRegions 一致：I2 为 mat2gray）
        bb = new_bboxes(kk,:);
        if any(isnan(bb)) || numel(bb)~=4
            continue;
        end
        x1 = max(1, floor(bb(1))+1);
        y1 = max(1, floor(bb(2))+1);
        x2 = min(W2, floor(bb(1)+bb(3)));
        y2 = min(H2, floor(bb(2)+bb(4)));
        if x2<x1 || y2<y1
            continue;
        end
        crop = I2(y1:y2, x1:x2);
        hh = min(size(band,1), size(crop,1));
        ww = min(size(band,2), size(crop,2));
        if hh<=0 || ww<=0
            continue;
        end
        b2 = band(1:hh,1:ww);
        v  = crop(1:hh,1:ww);
        vv = v(b2);
        if ~isempty(vv)
            memIntensity(kk) = mean(double(vv), 'omitnan');
        end
    end
end

GUVDataOut.memBandMasks = memBandMasks;
GUVDataOut.meanIntensities_mem = memIntensity;

% 其它字段尽量继承（如 imageSize/I 等）
copyList = {'imageSize','I','innerMask','memMask'};
for k = 1:numel(copyList)
    fn = copyList{k};
    if isfield(GUVDataIn,fn)
        GUVDataOut.(fn) = GUVDataIn.(fn);
    end
end

end

% ======================= helper =======================
function v = getFieldOr(S, fn, fallback)
if isfield(S,fn)
    v = S.(fn);
else
    v = fallback;
end
end

function [bestIoU,bestIdx] = bestIoUWithPrev(bb, m, bbPrev, mPrev)
bestIoU = 0; bestIdx = 0;
for j = 1:size(bbPrev,1)
    if j>numel(mPrev) || isempty(mPrev{j}), continue; end
    iou = iouFromBBoxSubMask(bb, m, bbPrev(j,:), mPrev{j});
    if iou > bestIoU
        bestIoU = iou;
        bestIdx = j;
    end
end
end

function iou = iouFromBBoxSubMask(bb1, m1, bb2, m2)
% bb: [x y w h]，m: logical(h,w)
% 通过 bbox 交集对齐计算 IoU（不构造整图）

% rounding for safety
x1 = round(bb1(1)); y1 = round(bb1(2)); w1 = round(bb1(3)); h1 = round(bb1(4));
x2 = round(bb2(1)); y2 = round(bb2(2)); w2 = round(bb2(3)); h2 = round(bb2(4));

if w1<=0 || h1<=0 || w2<=0 || h2<=0
    iou = 0; return;
end

ax1 = x1; ay1 = y1; ax2 = x1 + w1 - 1; ay2 = y1 + h1 - 1;
bx1 = x2; by1 = y2; bx2 = x2 + w2 - 1; by2 = y2 + h2 - 1;

ix1 = max(ax1,bx1); iy1 = max(ay1,by1);
ix2 = min(ax2,bx2); iy2 = min(ay2,by2);

if ix1>ix2 || iy1>iy2
    iou = 0; return;
end

% indices into m1
m1x1 = ix1 - ax1 + 1; m1y1 = iy1 - ay1 + 1;
m1x2 = ix2 - ax1 + 1; m1y2 = iy2 - ay1 + 1;
% indices into m2
m2x1 = ix1 - bx1 + 1; m2y1 = iy1 - by1 + 1;
m2x2 = ix2 - bx1 + 1; m2y2 = iy2 - by1 + 1;

% crop
a = logical(m1(m1y1:m1y2, m1x1:m1x2));
b = logical(m2(m2y1:m2y2, m2x1:m2x2));

inter = nnz(a & b);
if inter==0
    iou = 0; return;
end

areaA = nnz(m1);
areaB = nnz(m2);
uni = areaA + areaB - inter;
iou = inter / max(uni, eps);
end

function [x1,y1,x2,y2] = bboxExpandClamp(bb, margin, H, W)
% bbox [x y w h] -> expanded clamped coords
x = round(bb(1)); y = round(bb(2)); w = round(bb(3)); h = round(bb(4));
if w<1, w=1; end
if h<1, h=1; end
x1 = max(1, x - margin);
y1 = max(1, y - margin);
x2 = min(W, x + w - 1 + margin);
y2 = min(H, y + h - 1 + margin);
end

function [new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries] = ...
    appendOriginal(i, G, new_centroids, new_major, new_areas, new_filled, new_perim, new_meanI, new_bboxes, new_subMasks, new_boundaries)

if isfield(G,'centroids') && size(G.centroids,1)>=i
    new_centroids(end+1,:) = G.centroids(i,:); %#ok<AGROW>
end
if isfield(G,'majorAxisLength') && numel(G.majorAxisLength)>=i
    new_major(end+1,1) = G.majorAxisLength(i); %#ok<AGROW>
else
    new_major(end+1,1) = NaN; %#ok<AGROW>
end

A = getFieldOr(G,'Areas',[]);
if numel(A)>=i
    new_areas(end+1,1) = A(i); %#ok<AGROW>
else
    new_areas(end+1,1) = NaN; %#ok<AGROW>
end
FA = getFieldOr(G,'filledAreas',[]);
if numel(FA)>=i
    new_filled(end+1,1) = FA(i); %#ok<AGROW>
else
    new_filled(end+1,1) = new_areas(end); %#ok<AGROW>
end
P = getFieldOr(G,'Perimeters',[]);
if numel(P)>=i
    new_perim(end+1,1) = P(i); %#ok<AGROW>
else
    new_perim(end+1,1) = NaN; %#ok<AGROW>
end
MI = getFieldOr(G,'meanIntensities',[]);
if numel(MI)>=i
    new_meanI(end+1,1) = MI(i); %#ok<AGROW>
else
    new_meanI(end+1,1) = NaN; %#ok<AGROW>
end

if isfield(G,'bboxes') && size(G.bboxes,1)>=i
    new_bboxes(end+1,:) = G.bboxes(i,:); %#ok<AGROW>
else
    new_bboxes(end+1,:) = [NaN NaN NaN NaN]; %#ok<AGROW>
end

if isfield(G,'subMasks') && numel(G.subMasks)>=i
    new_subMasks{end+1,1} = G.subMasks{i}; %#ok<AGROW>
else
    new_subMasks{end+1,1} = []; %#ok<AGROW>
end

if isfield(G,'boundaries') && numel(G.boundaries)>=i
    new_boundaries{end+1,1} = G.boundaries{i}; %#ok<AGROW>
else
    new_boundaries{end+1,1} = []; %#ok<AGROW>
end

end
