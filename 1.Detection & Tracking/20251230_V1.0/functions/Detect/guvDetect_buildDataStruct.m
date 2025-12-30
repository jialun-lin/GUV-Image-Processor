function [Data, Geom] = guvDetect_buildDataStruct(I_norm, imageSize, mask, stats, opts, isInner)
%GUVDETECT_BUILDDATASTRUCT 将 regionprops(stats) 转为 Data 结构，并计算 SymScore/轴对称几何。
% 输入：
%   I_norm    : mat2gray 后的强度图（double, [0,1]）
%   imageSize : [H W]
%   mask      : full-image binary mask
%   stats     : regionprops 输出（需含 Image, BoundingBox 等）
%   opts      : guvDetect_defaultOpts 生成的 opts（包含 geom.enable 等）
%   isInner   : true=内水候选；false=膜候选
% 输出：
%   Data : 与原 detectGUVRegions 一致的字段集合
%   Geom : 轴对称几何字段集合

if nargin < 6, isInner = true; end

if isempty(stats)
    Data = struct();
    Data.I = I_norm;
    Data.imageSize = imageSize;
    Data.centroids = [];
    Data.majorAxisLength = [];
    Data.Areas = [];
    Data.FilledAreas = [];
    Data.filledAreas = []; % 兼容旧字段命名

    Data.Orientation = [];
    Data.Perimeter = [];
    Data.Perimeters = [];  % 兼容旧字段命名

    Data.SymScore = [];
    Data.meanIntensities = [];
    Data.boundaries = {};
    Data.bboxes = zeros(0,4);
    Data.subMasks = {};
    if isInner
        Data.innerMask = mask;
    else
        Data.memMask = mask; % 约定：memMask 为二值1的膜候选
    end
    Geom = guvDetect_initGeomList(0);
    return;
end

centroids       = cat(1, stats.Centroid);
majorAxisLength = [stats.MajorAxisLength]';
Areas           = [stats.Area]';
FilledAreas     = [stats.FilledArea]';
filledAreas     = FilledAreas; % 兼容旧字段命名

Orientation     = [stats.Orientation]';
Perimeter       = [stats.Perimeter]';
Perimeters      = Perimeter; % 兼容旧字段命名

if isfield(stats, 'MeanIntensity')
    meanIntensities = [stats.MeanIntensity]';
else
    meanIntensities = nan(numel(stats),1);
end

% ---- boundaries (full-image coordinates) ----
boundaries = cell(numel(stats),1);
for k = 1:numel(stats)
    if ~isfield(stats, 'BoundingBox') || isempty(stats(k).Image)
        boundaries{k} = [];
        continue;
    end
    sub = stats(k).Image;
    if ~isInner
        sub = imfill(sub, 'holes');
    end
    B = bwboundaries(sub, 8, 'noholes');
    if isempty(B)
        boundaries{k} = [];
        continue;
    end
    lens = cellfun(@(x) size(x,1), B);
    [~, idm] = max(lens);
    b = B{idm};
    bb = stats(k).BoundingBox;
    x = b(:,2) + bb(1) - 1;
    y = b(:,1) + bb(2) - 1;
    boundaries{k} = [x y];
end

% ---- SymScore ----
SymScore = nan(numel(stats),1);
for k = 1:numel(stats)
    SymScore(k) = guvDetect_calcSymScore(stats(k).Image, stats(k).Orientation);
end

% ---- axisymmetric geometry ----
Geom = guvDetect_initGeomList(numel(stats));
if isfield(opts,'geom') && isfield(opts.geom,'enable') && opts.geom.enable
    for k = 1:numel(stats)
        subMask = stats(k).Image;
        if ~any(subMask(:)), continue; end
        if ~isInner
            subMask = imfill(subMask, 'holes');
        end
        geo = guvDetect_axisymGeomFromMask(subMask, stats(k).Orientation, opts.pixel_size, opts.geom);
        Geom.A_axisym(k)   = geo.A_axisym;
        Geom.V_axisym(k)   = geo.V_axisym;
        Geom.Rve(k)        = geo.Rve;
        Geom.nu(k)         = geo.nu;
        Geom.IM(k)         = geo.IM;
        Geom.IG(k)         = geo.IG;
        Geom.IG_relerr(k)  = geo.IG_relerr;
        Geom.M_areaMean(k) = geo.M_areaMean;
        Geom.M_std(k)      = geo.M_std;
        Geom.Ks_mean(k)    = geo.Ks_mean;
        Geom.Kphi_mean(k)  = geo.Kphi_mean;
        Geom.neck_r(k)     = geo.neck_r;
    end
end

Data = struct();
Data.I = I_norm;
Data.imageSize = imageSize;
Data.centroids = centroids;
Data.majorAxisLength = majorAxisLength;
Data.Areas = Areas;
Data.FilledAreas = FilledAreas;
Data.filledAreas = filledAreas; % 兼容旧字段命名

Data.Orientation = Orientation;
Data.Perimeter = Perimeter;
Data.Perimeters = Perimeters; % 兼容旧字段命名

Data.SymScore = SymScore;
Data.meanIntensities = meanIntensities;
Data.boundaries = boundaries;

% ---- instance masks (bbox + subMask) ----
try
    Data.bboxes = reshape([stats.BoundingBox], 4, []).';
catch
    Data.bboxes = zeros(numel(stats),4);
    for k = 1:numel(stats)
        Data.bboxes(k,:) = stats(k).BoundingBox;
    end
end
Data.subMasks = reshape({stats.Image}, [], 1);

if isInner
    Data.innerMask = mask;
else
    Data.memMask = mask;
end

end
