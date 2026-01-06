function Info = guvPipeline_getChannelInfo(Cfg)
%GUVGETCHANNELINFO 解析通道配置（CList/CNames/CType 等）
% =========================================================================
% 本函数把 Cfg.Read 中的多通道信息整理成一个结构体，供 Pipeline/Series 使用。
%
% 重要说明：
%   - Cfg.Read.CType 仅用于“识别阶段如何构造 mask”（inner / mem）
%   - 主ref mask 的选择是“每个对象动态决定”的：
%       双通道时，同一对象若两通道都存在，则取 imfill 后面积更大者为主ref。
%   - 因此 Info.RefC 只用于：输出目录组织/FrameStore显示背景，不代表 ref masks 固定来自该通道。
%
% 输出：
%   Info.CList, Info.CNames, Info.CType
%   Info.RefC, Info.RefName  (用于输出目录命名)
%   Info.OtherCList          (除RefC外其余通道，常用于视频/检查)

Info = struct();

% --------- CList / CNames / CType ---------
Info.CList  = Cfg.Read.CList(:)';
Info.CNames = Cfg.Read.CNames;
Info.CType  = Cfg.Read.CType;

if numel(Info.CList) ~= numel(Info.CNames) || numel(Info.CList) ~= numel(Info.CType)
    error('Cfg.Read.CList / CNames / CType 长度必须一致。');
end

% --------- RefC（仅用于输出组织/显示背景）---------
Info.RefC = Cfg.Read.RefC;
idx = find(Info.CList == Info.RefC, 1, 'first');
if isempty(idx)
    % 若用户填错，则回退为第一个通道
    idx = 1;
    Info.RefC = Info.CList(1);
end
Info.RefName = Info.CNames{idx};

% --------- OtherCList ---------
Info.OtherCList = Info.CList;
Info.OtherCList(Info.OtherCList == Info.RefC) = [];



% --------- OtherC（用于双通道Debug视频/面板；不参与主ref mask选择）---------
Info.OtherC = [];
Info.OtherName = '';
if isfield(Cfg.Read,'OtherC') && ~isempty(Cfg.Read.OtherC)
    Info.OtherC = Cfg.Read.OtherC;
end
if isempty(Info.OtherC) && ~isempty(Info.OtherCList)
    Info.OtherC = Info.OtherCList(1);
end
if ~isempty(Info.OtherC)
    j = find(Info.CList == Info.OtherC, 1, 'first');
    if ~isempty(j)
        Info.OtherName = Info.CNames{j};
    end
end
end
