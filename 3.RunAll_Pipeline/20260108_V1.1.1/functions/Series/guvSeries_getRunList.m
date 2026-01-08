function [RunList, usePar] = guvSeries_getRunList(Cfg, nSeries)
%GUVSERIES_GETRUNLIST 生成要处理的Series列表（XY视野列表）
% -------------------------------------------------------------------------
% 兼容旧版 Series_GUVTrack_GetRunList.m 的行为：
%   - 若用户指定 Cfg.Read.SelectXYs，则只跑这些XY
%   - 否则默认跑全部 1:nSeries
% 并行开关：
%   - Cfg.Parallel.Enable 控制是否 parfor
% -------------------------------------------------------------------------
usePar = false;
if isfield(Cfg,'Parallel') && isfield(Cfg.Parallel,'Enable')
    usePar = logical(Cfg.Parallel.Enable);
end

RunList = 1:nSeries;
if isfield(Cfg,'Read') && isfield(Cfg.Read,'SelectXYs') && ~isempty(Cfg.Read.SelectXYs)
    RunList = Cfg.Read.SelectXYs(:)';
end

% 简单合法性裁剪
RunList = RunList(RunList>=1 & RunList<=nSeries);
RunList = unique(RunList, 'stable');
end
