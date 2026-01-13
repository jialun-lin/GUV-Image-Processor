function [CList, CNames] = guvPipeline_getChannelList(Cfg)
%GUVGETCHANNELLIST 从 Cfg 中解析要处理的通道列表与名字
if isfield(Cfg,'Read') && isfield(Cfg.Read,'CList') && ~isempty(Cfg.Read.CList)
    CList = Cfg.Read.CList;
else
    CList = Cfg.Read.C;
end
if isfield(Cfg,'Read') && isfield(Cfg.Read,'CNames') && ~isempty(Cfg.Read.CNames)
    CNames = Cfg.Read.CNames;
else
    CNames = arrayfun(@(c) sprintf('C%02d',c), CList, 'UniformOutput', false);
end
end
