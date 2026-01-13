function Geom = guvDetect_initGeomList(N)
%GUVDETECT_INITGEOMLIST 初始化轴对称几何字段容器。
if nargin < 1, N = 0; end
Geom = struct();
Geom.A_axisym   = nan(N,1);
Geom.V_axisym   = nan(N,1);
Geom.Rve        = nan(N,1);
Geom.nu         = nan(N,1);
Geom.IM         = nan(N,1);
Geom.IG         = nan(N,1);
Geom.IG_relerr  = nan(N,1);
Geom.M_areaMean = nan(N,1);
Geom.M_std      = nan(N,1);
Geom.Ks_mean    = nan(N,1);
Geom.Kphi_mean  = nan(N,1);
Geom.neck_r     = nan(N,1);
end
