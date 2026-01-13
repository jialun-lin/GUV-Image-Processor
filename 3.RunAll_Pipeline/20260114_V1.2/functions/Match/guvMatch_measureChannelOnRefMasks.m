function GUVDataRef = guvMatch_measureChannelOnRefMasks(GUVDataRef, Iother, otherC, otherType, Cfg, DetectOpts)
%GUVMATCH_MEASURECHANNELONREFMASKS
% 在“参考对象(Ref)”的 masks 上测量其它通道强度，并写回到 GUVDataRef。
% -------------------------------------------------------------------------
% 核心思想（你确认的最终版本）：
%   - 不再对其它通道单独做检测/分割/配对（那样调试成本高且容易字段不一致）
%   - 参考通道 RefC 产生唯一对象集合（实心 innerMask 对象）
%   - 对其它通道图像 Iother：
%       * meanIntensity_inner：用 Ref 的 subMasks 测均值
%       * meanIntensity_mem  ：用 Ref 的 memBandMasks 测均值
%       * bgMean             ：按该通道 CType 构造bgMask并测背景均值（可选每通道独立）
%
% 输入：
%   GUVDataRef : 参考通道检测结果（含 bboxes/subMasks/memBandMasks）
%   Iother     : 其它通道同一帧图像
%   otherC     : 其它通道索引（用于字段命名 *_Cxx）
%   otherType  : 其它通道 CType（仅用于背景估计）
%   DetectOpts : Detect配置（复用阈值参数用于背景估计）
%
% 输出：
%   GUVDataRef 追加三个字段：
%     meanIntensities_inner_Cxx
%     meanIntensities_mem_Cxx
%     meanIntensities_bg_Cxx
% -------------------------------------------------------------------------

if nargin < 4 || isempty(otherType), otherType = 'inner'; end
if nargin < 5, Cfg = struct(); end
if nargin < 6, DetectOpts = struct(); end

% 目标对象数
n = 0;
if isfield(GUVDataRef,'bboxes') && ~isempty(GUVDataRef.bboxes)
    n = size(GUVDataRef.bboxes,1);
elseif isfield(GUVDataRef,'centroids') && ~isempty(GUVDataRef.centroids)
    n = size(GUVDataRef.centroids,1);
end

fnInner = sprintf('meanIntensities_inner_C%02d', otherC);
fnMem   = sprintf('meanIntensities_mem_C%02d',   otherC);
fnBg    = sprintf('meanIntensities_bg_C%02d',    otherC);

if n == 0 || isempty(Iother)
    GUVDataRef.(fnInner) = nan(n,1);
    GUVDataRef.(fnMem)   = nan(n,1);
    GUVDataRef.(fnBg)    = nan(n,1);
    return;
end

I_raw = double(Iother);
% I_norm = mat2gray(Iother);

% inner：实心 subMasks
innerMean = nan(n,1);
if isfield(GUVDataRef,'bboxes') && isfield(GUVDataRef,'subMasks')
    innerMean = guvMatch_meanOnBBoxMasks(I_raw, GUVDataRef.bboxes, GUVDataRef.subMasks);
end

% mem：轮廓环带 memBandMasks
memMean = nan(n,1);
if isfield(GUVDataRef,'bboxes') && isfield(GUVDataRef,'memBandMasks')
    memMean = guvMatch_meanOnBBoxMasks(I_raw, GUVDataRef.bboxes, GUVDataRef.memBandMasks);
end

% bg：每通道独立估计（更稳健；与旧版一致的默认行为）
bgMean = guvMatch_computeBgMean(Iother, otherType, DetectOpts);
GUVDataRef.(fnInner) = innerMean;
GUVDataRef.(fnMem)   = memMean;
GUVDataRef.(fnBg)    = repmat(bgMean, n, 1);
end