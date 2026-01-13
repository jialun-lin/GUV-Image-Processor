function geo = guvDetect_axisymGeomFromMask(mask, orientationDeg, pixel_size, gopt)
% Returns scalars:
% A_axisym, V_axisym, Rve, nu, IM, IG, IG_relerr, M_areaMean, M_std,
% Ks_mean, Kphi_mean, neck_r

    geo = struct();
    geo.A_axisym = NaN; geo.V_axisym = NaN; geo.Rve = NaN; geo.nu = NaN;
    geo.IM = NaN; geo.IG = NaN; geo.IG_relerr = NaN;
    geo.M_areaMean = NaN; geo.M_std = NaN;
    geo.Ks_mean = NaN; geo.Kphi_mean = NaN;
    geo.neck_r = NaN;

    if ~any(mask(:)), return; end

    % ---- boundary ----
    B = bwboundaries(mask, 'noholes');
    if isempty(B), return; end
    % pick the longest boundary
    Lb = cellfun(@(x) size(x,1), B);
    [~, id] = max(Lb);
    b = B{id};               % [row, col]
    x = double(b(:,2));      % col
    y = double(b(:,1));      % row

    % ---- centroid in local patch ----
    rp = regionprops(mask, 'Centroid');
    c = rp.Centroid;
    x = x - c(1);
    y = y - c(2);

    % ---- rotate: align major axis to +y (same convention as SymScore) ----
    theta = deg2rad(90 - orientationDeg);
    R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
    xy = R * [x'; y'];
    xr = xy(1,:)';
    zr = xy(2,:)';

    % ---- find poles (north: max z, south: min z) with minimal |x| in top/bottom bands ----
    zmax = max(zr); zmin = min(zr);
    zspan = max(zmax - zmin, eps);
    band = gopt.poleZFrac * zspan;

    candN = find(zr >= zmax - band);
    candS = find(zr <= zmin + band);
    if isempty(candN) || isempty(candS), return; end

    [~, kN] = min(abs(xr(candN)));
    [~, kS] = min(abs(xr(candS)));
    iN = candN(kN);
    iS = candS(kS);

    N = numel(xr);

    % ---- two possible paths between iN and iS ----
    idx1 = guvDetect_boundaryPath(iN, iS, N, +1);
    idx2 = guvDetect_boundaryPath(iN, iS, N, -1);

    frac1 = mean(xr(idx1) >= 0);
    frac2 = mean(xr(idx2) >= 0);

    if frac2 > frac1
        idx = idx2;
    else
        idx = idx1;
    end

    xh = xr(idx);
    zh = zr(idx);

    % enforce "right meridian": radial r = |x|
    r_raw = abs(xh) * pixel_size;
    z_raw = zh * pixel_size;

    if numel(r_raw) < 10, return; end

    % enforce endpoints r=0 (pole constraint)
    r_raw(1) = 0; r_raw(end) = 0;

    % ---- arc-length parameter s ----
    ds = sqrt(diff(r_raw).^2 + diff(z_raw).^2);
    s_raw = [0; cumsum(ds)];
    Ltot = s_raw(end);
    if Ltot <= 0 || ~isfinite(Ltot), return; end

    s = linspace(0, Ltot, gopt.nSamples)';

    % ---- smoothing r(s), z(s) ----
    if exist('csaps','file') == 2
        ppr = csaps(s_raw, r_raw, gopt.spline_p);
        ppz = csaps(s_raw, z_raw, gopt.spline_p);
        r = fnval(ppr, s);
        z = fnval(ppz, s);

        dr  = fnval(fnder(ppr,1), s);
        dz  = fnval(fnder(ppz,1), s);
        d2r = fnval(fnder(ppr,2), s);
        d2z = fnval(fnder(ppz,2), s);
    else
        % fallback: pchip + smoothdata + finite diff
        r0 = interp1(s_raw, r_raw, s, 'pchip', 'extrap');
        z0 = interp1(s_raw, z_raw, s, 'pchip', 'extrap');
        r = smoothdata(r0, 'gaussian', gopt.smooth_window);
        z = smoothdata(z0, 'gaussian', gopt.smooth_window);

        dr  = gradient(r, s);
        dz  = gradient(z, s);
        d2r = gradient(dr, s);
        d2z = gradient(dz, s);
    end

    r(1) = 0; r(end) = 0;

    % ---- geometry: curvature ----
    psi = atan2(dz, dr);   % tangent angle

    % kappa_s: curvature of meridian in (r,z) plane
    den = (dr.^2 + dz.^2).^(3/2);
    den = max(den, eps);
    kappa_s = (dr .* d2z - dz .* d2r) ./ den;

    % kappa_phi: azimuthal curvature
    rr = max(r, gopt.eps_r);
    kappa_phi = sin(psi) ./ rr;

    % handle poles: r~0 => set kappa_phi = kappa_s
    poleMask = (r < 10*gopt.eps_r);
    kappa_phi(poleMask) = kappa_s(poleMask);

    M = 0.5 * (kappa_s + kappa_phi);
    K = kappa_s .* kappa_phi;

    ds_w = gradient(s);

    dA = 2*pi * r .* ds_w;                 % area element
    A_axisym = sum(dA, 'omitnan');

    % volume: dV = pi r^2 dz = pi r^2 (dz/ds) ds
    V_axisym = abs(sum(pi * (r.^2) .* dz .* ds_w, 'omitnan'));

    if ~(isfinite(A_axisym) && A_axisym > 0 && isfinite(V_axisym) && V_axisym > 0)
        return;
    end

    Rve = sqrt(A_axisym/(4*pi));
    nu  = 6*sqrt(pi) * V_axisym / (A_axisym^(3/2));

    IM = sum(M .* dA, 'omitnan');
    IG = sum(K .* dA, 'omitnan');
    IG_relerr = abs(IG - 4*pi) / (4*pi);

    M_areaMean = IM / A_axisym;
    M_std = std(M(isfinite(M)));

    Ks_mean   = mean(kappa_s(isfinite(kappa_s)));
    Kphi_mean = mean(kappa_phi(isfinite(kappa_phi)));

    neck_r = min(r(isfinite(r)));

    geo.A_axisym   = A_axisym;
    geo.V_axisym   = V_axisym;
    geo.Rve        = Rve;
    geo.nu         = nu;
    geo.IM         = IM;
    geo.IG         = IG;
    geo.IG_relerr  = IG_relerr;
    geo.M_areaMean = M_areaMean;
    geo.M_std      = M_std;
    geo.Ks_mean    = Ks_mean;
    geo.Kphi_mean  = Kphi_mean;
    geo.neck_r     = neck_r;
end

