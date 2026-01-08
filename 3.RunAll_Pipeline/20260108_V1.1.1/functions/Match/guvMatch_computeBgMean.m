function bgMean = guvMatch_computeBgMean(I, CType, DetectOpts)
%GUVMATCH_COMPUTEBGMEAN 为“某一通道”估计背景均值（标量）
% -------------------------------------------------------------------------
% 说明：
%   - 背景均值用于输出 meanIntensities_bg_Cxx
%   - 这里的 CType 与检测阶段一致，仅用于构造 bgMask
%     * CType='inner'：bgMask = ~innerMask
%     * CType='mem'  ：先取memMask(oneMask)，zeroMask=~memMask，再用flood-fill得到bgMask
%   - 最终 bgMean 在 mat2gray(I) 归一化空间计算（与其它强度字段一致）
% -------------------------------------------------------------------------

if nargin < 2 || isempty(CType), CType = 'inner'; end
if nargin < 3, DetectOpts = struct(); end
binOpt = struct(); innerOpt = struct();
if isfield(DetectOpts,'bin'), binOpt = DetectOpts.bin; end
if isfield(DetectOpts,'inner'), innerOpt = DetectOpts.inner; end

I_raw = double(I);  
[I_norm, oneMask] = guvDetect_binarizeAdaptive(I, binOpt);

CType = lower(string(CType));
if CType ~= "inner" && CType ~= "mem"
    CType = "inner";
end

switch CType
    case "inner"
        innerMask = imfill(oneMask, 'holes');
        if isfield(innerOpt,'areaOpen') && innerOpt.areaOpen > 0
            innerMask = bwareaopen(innerMask, innerOpt.areaOpen);
        end
        bgMask = ~innerMask;
    otherwise
        memMask = oneMask;
        zeroMask = ~memMask;
        bgMask = guvDetect_backgroundFloodFill(zeroMask, innerOpt);
end

if any(bgMask(:))
    bgMean = mean(double(I_raw(bgMask)), 'omitnan');
else
    bgMean = mean(double(I_raw(:)), 'omitnan');
end
if isempty(bgMean) || isnan(bgMean), bgMean = 0; end
end
