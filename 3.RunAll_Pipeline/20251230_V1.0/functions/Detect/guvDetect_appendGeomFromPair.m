function geomList = guvDetect_appendGeomFromPair(geomList, Geom1, i, Geom2, j)
%GUVDETECT_APPENDGEOMFROMPAIR 将两个来源的几何量做平均(omitnan)后追加。
geomList.A_axisym   = [geomList.A_axisym;   mean([Geom1.A_axisym(i),   Geom2.A_axisym(j)],   'omitnan')];
geomList.V_axisym   = [geomList.V_axisym;   mean([Geom1.V_axisym(i),   Geom2.V_axisym(j)],   'omitnan')];
geomList.Rve        = [geomList.Rve;        mean([Geom1.Rve(i),        Geom2.Rve(j)],        'omitnan')];
geomList.nu         = [geomList.nu;         mean([Geom1.nu(i),         Geom2.nu(j)],         'omitnan')];
geomList.IM         = [geomList.IM;         mean([Geom1.IM(i),         Geom2.IM(j)],         'omitnan')];
geomList.IG         = [geomList.IG;         mean([Geom1.IG(i),         Geom2.IG(j)],         'omitnan')];
geomList.IG_relerr  = [geomList.IG_relerr;  mean([Geom1.IG_relerr(i),  Geom2.IG_relerr(j)],  'omitnan')];
geomList.M_areaMean = [geomList.M_areaMean; mean([Geom1.M_areaMean(i), Geom2.M_areaMean(j)], 'omitnan')];
geomList.M_std      = [geomList.M_std;      mean([Geom1.M_std(i),      Geom2.M_std(j)],      'omitnan')];
geomList.Ks_mean    = [geomList.Ks_mean;    mean([Geom1.Ks_mean(i),    Geom2.Ks_mean(j)],    'omitnan')];
geomList.Kphi_mean  = [geomList.Kphi_mean;  mean([Geom1.Kphi_mean(i),  Geom2.Kphi_mean(j)],  'omitnan')];
geomList.neck_r     = [geomList.neck_r;     mean([Geom1.neck_r(i),     Geom2.neck_r(j)],     'omitnan')];
end
