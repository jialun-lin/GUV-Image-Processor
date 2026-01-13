function Thr = guvSeries_buildPxThresholds(Cfg)
%GUVSERIES_BUILDPXTHRESHOLDS 将配置中的 um 阈值统一换算为像素（便于内部计算）
% -------------------------------------------------------------------------
% 约定：
%   - 输入 Cfg.*_um
%   - 输出 Thr.*_px
%   - Thr.px 保存像素尺寸（um/px），供其它模块用
%
% 本文件只做单位换算，不做任何算法判断。

px = Cfg.PixelSize_um;
Thr = struct();
Thr.px = px;

% ---- Detect ----
Thr.minMajor_px     = Cfg.Detect.MinMajor_um     / px;
Thr.maxMajor_px     = Cfg.Detect.MaxMajor_um     / px;
Thr.suppressDist_px = Cfg.Detect.SuppressDist_um / px;

% ---- Fuse（同帧配对距离）----
Thr.fuseDist_px     = Cfg.Fuse.Pair.MaxDist_um   / px;

% ---- Track ----
Thr.trackGate_px    = Cfg.Track.DistGate_um      / px;

end
