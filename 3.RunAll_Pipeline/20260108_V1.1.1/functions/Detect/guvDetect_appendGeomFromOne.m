function geomList = guvDetect_appendGeomFromOne(geomList, Geom, idx)
%GUVDETECT_APPENDGEOMFROMONE 将 Geom(idx) 追加到 geomList。
geomList.A_axisym   = [geomList.A_axisym;   Geom.A_axisym(idx)];
geomList.V_axisym   = [geomList.V_axisym;   Geom.V_axisym(idx)];
geomList.Rve        = [geomList.Rve;        Geom.Rve(idx)];
geomList.nu         = [geomList.nu;         Geom.nu(idx)];
geomList.IM         = [geomList.IM;         Geom.IM(idx)];
geomList.IG         = [geomList.IG;         Geom.IG(idx)];
geomList.IG_relerr  = [geomList.IG_relerr;  Geom.IG_relerr(idx)];
geomList.M_areaMean = [geomList.M_areaMean; Geom.M_areaMean(idx)];
geomList.M_std      = [geomList.M_std;      Geom.M_std(idx)];
geomList.Ks_mean    = [geomList.Ks_mean;    Geom.Ks_mean(idx)];
geomList.Kphi_mean  = [geomList.Kphi_mean;  Geom.Kphi_mean(idx)];
geomList.neck_r     = [geomList.neck_r;     Geom.neck_r(idx)];
end
