function GUVData = guvMatch_annotateChannelFluor(GUVData, C)
%GUVANNOTATECHANNELFLUOR 统一写入“当前通道自身”的强度字段
% 说明：
%   - 该函数不会做通道间映射，只把“当前通道”已有的 inner/bg/mem 强度
%     写成统一命名，便于后续导出与调试。

if nargin < 2 || isempty(C)
    C = 1;
end

fnInner = sprintf('meanIntensities_inner_C%02d', C);
fnBg    = sprintf('meanIntensities_bg_C%02d', C);
fnMem   = sprintf('meanIntensities_mem_C%02d', C);

% 对象数量
n = 0;
if isfield(GUVData,'centroids') && ~isempty(GUVData.centroids)
    n = size(GUVData.centroids,1);
elseif isfield(GUVData,'bboxes') && ~isempty(GUVData.bboxes)
    n = size(GUVData.bboxes,1);
elseif isfield(GUVData,'Areas') && ~isempty(GUVData.Areas)
    n = numel(GUVData.Areas);
end

inner = nan(n,1);
if isfield(GUVData,'meanIntensities') && ~isempty(GUVData.meanIntensities)
    v = GUVData.meanIntensities(:);
    inner(1:min(n,numel(v))) = v(1:min(n,numel(v)));
end

bg = NaN;
if isfield(GUVData,'bgMeanIntensity') && ~isempty(GUVData.bgMeanIntensity)
    bg = GUVData.bgMeanIntensity;
end

mem = nan(n,1);
if isfield(GUVData,'meanIntensities_mem') && ~isempty(GUVData.meanIntensities_mem)
    v = GUVData.meanIntensities_mem(:);
    mem(1:min(n,numel(v))) = v(1:min(n,numel(v)));
end

GUVData.(fnInner) = inner;
GUVData.(fnBg)    = repmat(bg, n, 1);
GUVData.(fnMem)   = mem;

end
