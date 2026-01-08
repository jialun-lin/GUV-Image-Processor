function [innerMask, bgMask, bgMeanIntensity] = guvDetect_computeInnerMask(I_norm, memMask, innerOpt, splitOpt)
%GUVDETECT_COMPUTEINNERMASK 从 memMask(1=mem)得到 innerMask 与背景 mask。
% 步骤：
%   1) zeroMask = ~memMask
%   2) 背景 bgMask = flood-fill(zeroMask, 顶部seed)
%   3) innerMask = zeroMask & ~bgMask
%   4) innerMask areaOpen + 可选 watershed 拆分

if nargin < 3, innerOpt = struct(); end
if nargin < 4, splitOpt = struct(); end
innerOpt = guvUtil_setDefault(innerOpt,'areaOpen',30);
innerOpt = guvUtil_setDefault(innerOpt,'seedRow',2);
innerOpt = guvUtil_setDefault(innerOpt,'nSeeds',10);

splitOpt = guvUtil_setDefault(splitOpt,'doSplit',true);
splitOpt = guvUtil_setDefault(splitOpt,'splitH',1.0);
splitOpt = guvUtil_setDefault(splitOpt,'openR',2);

zeroMask = ~logical(memMask);

bgMask = guvDetect_backgroundFloodFill(zeroMask, innerOpt);
innerMask = zeroMask & ~bgMask;

% 背景均值（单帧单通道标量）
bgMeanIntensity = mean(I_norm(bgMask), 'omitnan');
if isempty(bgMeanIntensity) || isnan(bgMeanIntensity)
    bgMeanIntensity = 0;
end

% 去小噪声
innerMask = bwareaopen(innerMask, innerOpt.areaOpen);

% 可选：密集/粘连拆分
if splitOpt.doSplit
    innerMask = imfill(innerMask, 'holes');
    innerMask = imopen(innerMask, strel('disk', splitOpt.openR));

    D = -bwdist(~innerMask);
    D = imhmin(D, splitOpt.splitH);
    Lw = watershed(D);

    innerMask(Lw == 0) = 0;
    innerMask = bwareaopen(innerMask, innerOpt.areaOpen);
end

end
