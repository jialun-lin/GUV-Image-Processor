function AllResults = guvCompute_Calculation(TTracks, ND2Path, SeriesID, Cfg)
%GUVCOMPUTE_CALCALLRESULTSFROMTRACKS 追踪后基于轴对称假设的动力学/形态学计算（单文件大函数版）
% =========================================================================
% 本函数来自你提供的 "GUV-Image-Processor-main" 中的 Calculation_program.mlx，
% 其核心逻辑为：
%   - 以追踪输出 TTracks 的 (centroids, majorAxisLength, frames) 为引导，
%     在原始图像上逐帧裁剪 ROI，并用阈值 + activecontour 得到目标轮廓。
%   - 将轮廓旋转到主轴坐标系，做傅里叶低频保留实现平滑。
%   - 以旋转后轮廓重建母线 r(z)，在轴对称假设下计算：
%       Area/Vol/Rve/nu/平均曲率/高斯曲率积分/约化弯曲能系数等。
%   - 额外计算左右镜像 IoU 作为对称性分数。
%   - 输出 AllResults(id) 结构体，并可保存为 AllResults.mat。
%
% 输入：
%   TTracks   : 追踪输出结构体数组（来自 guvTrack_trackCentroids）。
%   ND2Path   : 原始 ND2 文件路径（也可 lif/tif 等，只要 bfGetReader 支持）。
%   SeriesID  : 视野序号（MATLAB 1-based；内部会 setSeries(SeriesID-1)）。
%   Cfg       : 计算配置（结构体，可缺省字段）：
%       .Z            : Z 层 (默认 1)
%       .Channel      : 用于分割与轮廓重建的通道 (默认 1)
%       .PixelSize_um : 像素尺寸 um/px（默认 0.16；建议由 Pipeline 传入）
%       .n_keep       : 傅里叶保留低频数量（默认 12）
%       .IDs          : 要处理的轨迹 ID 列表；[] 表示全部（默认 []）
%       .OutputFolder : 输出目录（默认 ./Computation）
%       .SaveMAT      : 是否保存 AllResults.mat（默认 true）
%       .Verbose      : 打印进度（默认 true）
%
% 输出：
%   AllResults : 结构体数组（索引=轨迹ID），字段基本保持与原脚本一致。
%
% 依赖：bfGetReader / bfGetPlaneAtZCT（bfmatlab），以及 Image Processing Toolbox。

    if nargin < 4, Cfg = struct(); end

    % -------- 参数默认值 --------
    if exist('guvUtil_setDefault','file') == 2
        Cfg = guvUtil_setDefault(Cfg, 'Z', 1);
        Cfg = guvUtil_setDefault(Cfg, 'Channel', 1);
        Cfg = guvUtil_setDefault(Cfg, 'PixelSize_um', 0.16);
        Cfg = guvUtil_setDefault(Cfg, 'n_keep', 12);
        Cfg = guvUtil_setDefault(Cfg, 'IDs', []);
        Cfg = guvUtil_setDefault(Cfg, 'OutputFolder', fullfile(pwd,'Computation'));
        Cfg = guvUtil_setDefault(Cfg, 'SaveMAT', true);
        Cfg = guvUtil_setDefault(Cfg, 'Verbose', true);
    else
        if ~isfield(Cfg,'Z') || isempty(Cfg.Z), Cfg.Z = 1; end
        if ~isfield(Cfg,'Channel') || isempty(Cfg.Channel), Cfg.Channel = 1; end
        if ~isfield(Cfg,'PixelSize_um') || isempty(Cfg.PixelSize_um), Cfg.PixelSize_um = 0.16; end
        if ~isfield(Cfg,'n_keep') || isempty(Cfg.n_keep), Cfg.n_keep = 12; end
        if ~isfield(Cfg,'IDs'), Cfg.IDs = []; end
        if ~isfield(Cfg,'OutputFolder') || isempty(Cfg.OutputFolder), Cfg.OutputFolder = fullfile(pwd,'Computation'); end
        if ~isfield(Cfg,'SaveMAT') || isempty(Cfg.SaveMAT), Cfg.SaveMAT = true; end
        if ~isfield(Cfg,'Verbose') || isempty(Cfg.Verbose), Cfg.Verbose = true; end
    end

    if nargin < 3 || isempty(SeriesID)
        SeriesID = 1;
    end

    if nargin < 2 || isempty(ND2Path) || ~exist(ND2Path,'file')
        error('ND2Path 无效或不存在：%s', string(ND2Path));
    end

    if nargin < 1 || isempty(TTracks)
        AllResults = struct([]);
        return;
    end

    output_folder = Cfg.OutputFolder;
    if ~exist(output_folder, 'dir')
        mkdir(output_folder);
    end

    pixel_size = Cfg.PixelSize_um; % um/px
    n_keep = Cfg.n_keep;

    % -------- 打开 reader 并切换 series --------
    r = bfGetReader(ND2Path);
    r.setSeries(SeriesID-1);

    H = r.getSizeY();
    W = r.getSizeX();

    % -------- 选择要处理的 ID --------
    if ~isempty(Cfg.IDs)
        id_list = Cfg.IDs(:)';
    else
        id_list = 1:numel(TTracks);
    end

    if Cfg.Verbose
        fprintf('[Compute] Series=%d, 开始处理 %d 个轨迹...\n', SeriesID, numel(id_list));
    end

    % -------- 输出结构体（索引=轨迹ID）--------
    AllResults = repmat(struct(), 1, numel(TTracks));

    % -------- 主循环：遍历轨迹 --------
    for id_idx = 1:length(id_list)
        id = id_list(id_idx);
        if id < 1 || id > numel(TTracks)
            continue;
        end

        % 跳过空轨迹
        if ~isfield(TTracks(id),'frames') || isempty(TTracks(id).frames)
            continue;
        end

        frames = TTracks(id).frames;
        centroids_track = TTracks(id).centroids;
        majorAxisLength = TTracks(id).majorAxisLength;

        % 提取可选强度字段（如存在则原样搬运到 AllResults）
        fieldList = {'meanIntensities_bg_C01', 'meanIntensities_bg_C02', ...
                     'meanIntensities_inner_C01', 'meanIntensities_inner_C02', ...
                     'meanIntensities_mem_C01', 'meanIntensities_mem_C02'};
        for f = fieldList
            if isfield(TTracks(id), f{1})
                eval([f{1} ' = TTracks(id).' f{1} ';']); %#ok<EVLCS>
            else
                eval([f{1} ' = [];']); %#ok<EVLCS>
            end
        end

        num_files = length(frames);
        if Cfg.Verbose
            fprintf('[Compute] ID=%d, 帧数=%d ... ', id, num_files);
        end

        % ====== 初始化存储变量 ======
        volumes_px = zeros(num_files, 1);
        surfaces_px = zeros(num_files, 1);
        I_K_array = zeros(num_files, 1);
        M_tilde_array = zeros(num_files, 1);
        nu_array = zeros(num_files, 1);
        rb_array = zeros(num_files, 1);
        R_ve_array = zeros(num_files, 1);
        is_valid = false(num_files, 1);
        symmetry_score_array = zeros(num_files, 1);

        % 存储用于可视化的数据（预分配，避免字段不一致）
        stored_data = repmat(struct( ...
            'img_gray', [], 'boundary', [], 'centroids_reg', [], ...
            'x_rot', [], 'z_rot', [], 'r_f', [], 'z_f', [], 'frame', []), num_files, 1);

        % ====== 遍历该ID的所有帧 ======
        for i = 1:num_files
            t = frames(i);
            cx = centroids_track(i, 1);
            cy = centroids_track(i, 2);
            axisLen = majorAxisLength(i);

            try
                %% ====== 裁剪图像 ======
                cropSize = round(axisLen * 1.2);
                halfSize = round(cropSize / 2);

                x1 = max(1, round(cx - halfSize));
                x2 = min(W, round(cx + halfSize));
                y1 = max(1, round(cy - halfSize));
                y2 = min(H, round(cy + halfSize));

                I = bfGetPlaneAtZCT(r, Cfg.Z, Cfg.Channel, t);
                img = I(y1:y2, x1:x2);

                if size(img, 3) == 3
                    img = rgb2gray(img);
                end
                img_gray = img;

                img_center = [size(img,2)/2, size(img,1)/2];

                %% ====== 创建中心区域掩码 ======
                [img_h, img_w] = size(img_gray);
                [X_grid, Y_grid] = meshgrid(1:img_w, 1:img_h);

                center_radius = axisLen * 0.6;

                dist_from_center = sqrt((X_grid - img_center(1)).^2 + (Y_grid - img_center(2)).^2);
                center_mask = dist_from_center <= center_radius;

                %% ====== 分割 ======
                img_adj = imadjust(img_gray);

                level = graythresh(img_adj);

                bw_init = imbinarize(img_adj, level * 0.9);

                bw_init_center = bw_init & center_mask;
                bw_init_center = imfill(bw_init_center, 'holes');

                if sum(bw_init_center(:)) == 0
                    bw_init_center = imbinarize(img_adj, level * 0.5) & center_mask;
                    bw_init_center = imfill(bw_init_center, 'holes');
                end

                if sum(bw_init_center(:)) < 50
                    center_pixels = img_adj(center_mask);
                    local_level = graythresh(center_pixels);
                    bw_init_center = img_adj > (local_level * max(center_pixels)) & center_mask;
                    bw_init_center = imfill(bw_init_center, 'holes');
                end

                if sum(bw_init_center(:)) < 50
                    continue;
                end

                bw_init_center = bwareafilt(bw_init_center, 1);

                % 活动轮廓优化
                bw_refined = activecontour(img_adj, bw_init_center, 100, 'Chan-Vese', ...
                                           'SmoothFactor', 1, 'ContractionBias', -0.1);

                % 保留与中心区域有重叠的连通区域
                bw_refined_labeled = bwlabel(bw_refined);
                regions_in_center = unique(bw_refined_labeled(center_mask & bw_refined));
                regions_in_center = regions_in_center(regions_in_center > 0);

                bw_refined_center = false(size(bw_refined));
                for ri = 1:length(regions_in_center)
                    bw_refined_center = bw_refined_center | (bw_refined_labeled == regions_in_center(ri));
                end

                % 形态学清理
                bw_refined_center = imfill(bw_refined_center, 'holes');
                bw_refined_center = imopen(bw_refined_center, strel('disk', 2));

                % 获取所有区域
                stats = regionprops(bw_refined_center, 'Centroid', 'Area', 'PixelIdxList', ...
                                   'Orientation', 'MajorAxisLength', 'MinorAxisLength');

                if isempty(stats)
                    continue;
                end

                % 筛选并选择目标区域
                min_area = 200;
                valid_objs = find([stats.Area] > min_area);

                if isempty(valid_objs)
                    continue;
                end

                % 选择最靠近中心的区域
                centroids_valid = cat(1, stats(valid_objs).Centroid);
                dists = sqrt((centroids_valid(:,1) - img_center(1)).^2 + ...
                             (centroids_valid(:,2) - img_center(2)).^2);
                [~, closest_idx] = min(dists);
                target_idx = valid_objs(closest_idx);

                % 创建目标掩码
                bw_target = false(size(bw_refined_center));
                bw_target(stats(target_idx).PixelIdxList) = true;

                % 提取边界和质心
                boundaries = bwboundaries(bw_target);
                if isempty(boundaries)
                    continue;
                end
                boundary = boundaries{1};
                bnd = boundary;

                props_final = regionprops(bw_target, 'Centroid', 'Orientation');
                centroids_reg = props_final(1).Centroid;
                orient = props_final(1).Orientation;

                x_c = bnd(:,2) - centroids_reg(1);
                y_c = bnd(:,1) - centroids_reg(2);
                theta = deg2rad(orient + 90);
                R_mat = [cos(theta) -sin(theta); sin(theta) cos(theta)];
                rot_coords = R_mat * [x_c'; y_c'];
                x_rot = rot_coords(1,:)';
                z_rot = rot_coords(2,:)';

                %% ====== 傅里叶平滑 ======
                X_fft = fft(x_rot);
                Z_fft = fft(z_rot);
                X_fft(n_keep+1:end-n_keep+1) = 0;
                Z_fft(n_keep+1:end-n_keep+1) = 0;
                x_s = real(ifft(X_fft));
                z_s = real(ifft(Z_fft));
                x_s(end+1) = x_s(1);
                z_s(end+1) = z_s(1);

                %% ====== 提取母线 R(z) ======
                z_qs = linspace(min(z_s)*0.99, max(z_s)*0.99, 200)';
                r_qs = zeros(size(z_qs));

                for j = 1:length(z_qs)
                    crossings = [];
                    for k = 1:length(z_s)-1
                        if (z_s(k)-z_qs(j))*(z_s(k+1)-z_qs(j)) <= 0
                            t_interp = (z_qs(j)-z_s(k))/(z_s(k+1)-z_s(k)+eps);
                            crossings = [crossings; x_s(k)+t_interp*(x_s(k+1)-x_s(k))]; %#ok<AGROW>
                        end
                    end
                    if ~isempty(crossings)
                        r_qs(j) = (max(crossings)-min(crossings))/2;
                    end
                end

                r_qs = smoothdata(r_qs, 'gaussian', 5);
                r_qs(1) = 0;
                r_qs(end) = 0;

                %% ====== 弧长重采样与曲率计算 ======
                ds_v = sqrt(diff(r_qs).^2 + diff(z_qs).^2);
                s_a = [0; cumsum(ds_v)];
                s_u = linspace(0, s_a(end), 300)';

                % csaps 依赖 Curve Fitting Toolbox（部分 MATLAB 安装可能没有）。
                % 若缺失，则退化为 pchip 插值 + 数值梯度，保证代码可运行。
                if exist('csaps','file') == 2 && exist('fnval','file') == 2 && exist('fnder','file') == 2
                    pp_r = csaps(s_a, r_qs, 0.999);
                    pp_z = csaps(s_a, z_qs, 0.999);
                    rf = fnval(pp_r, s_u);
                    zf = fnval(pp_z, s_u);
                    dr  = fnval(fnder(pp_r, 1), s_u);
                    dz  = fnval(fnder(pp_z, 1), s_u);
                    ddr = fnval(fnder(pp_r, 2), s_u);
                    ddz = fnval(fnder(pp_z, 2), s_u);
                else
                    rf = interp1(s_a, r_qs, s_u, 'pchip', 'extrap');
                    zf = interp1(s_a, z_qs, s_u, 'pchip', 'extrap');
                    dr  = gradient(rf, s_u);
                    dz  = gradient(zf, s_u);
                    ddr = gradient(dr, s_u);
                    ddz = gradient(dz, s_u);
                end

                rf(1) = 0; rf(end) = 0;

                r_f = rf;
                z_f = zf;

                ks = (dr.*ddz - dz.*ddr) ./ (dr.^2 + dz.^2).^1.5;
                psi = atan2(dz, dr);
                kphi = zeros(size(rf));
                val = rf > max(rf)*0.03;
                kphi(val) = sin(psi(val)) ./ rf(val);
                kphi(~val) = ks(~val);

                M = (ks + kphi) / 2;
                K = ks .* kphi;
                ds_inc = s_u(2) - s_u(1);
                dA = 2 * pi * rf * ds_inc;

                %% ====== 计算物理量 ======
                Area = sum(dA);
                Vol = abs(sum(pi * rf.^2 .* dz * ds_inc));
                R_ve = sqrt(Area / (4*pi));

                volumes_px(i) = Vol;
                surfaces_px(i) = Area;
                R_ve_array(i) = R_ve;
                nu_array(i) = 6 * sqrt(pi) * Vol / (Area^1.5);
                I_K_array(i) = sum(K .* dA);
                M_tilde_array(i) = sum(M .* dA) / (4*pi*R_ve);
                rb_array(i) = sum(M.^2 .* dA) / (4*pi);
                is_valid(i) = true;

                %% ====== 计算对称性得分（IoU方法） ======
                rotated_mask = imrotate(bw_target, -orient, 'bilinear', 'crop');
                props_rot = regionprops(rotated_mask, 'Centroid');
                if ~isempty(props_rot)
                    x_c_sym = round(props_rot(1).Centroid(1));
                    if x_c_sym > 1 && x_c_sym < size(rotated_mask, 2)
                        L = rotated_mask(:, 1:x_c_sym);
                        R = rotated_mask(:, x_c_sym+1:end);

                        width_L = size(L, 2);
                        width_R = size(R, 2);
                        max_width = max(width_L, width_R);

                        L_flipped = fliplr(L);

                        if width_L < max_width
                            L_flipped = [L_flipped, false(size(L,1), max_width - width_L)]; %#ok<AGROW>
                        end
                        if width_R < max_width
                            R_padded = [R, false(size(R,1), max_width - width_R)]; %#ok<AGROW>
                        else
                            R_padded = R;
                        end

                        intersection = L_flipped & R_padded;
                        union_area = L_flipped | R_padded;

                        area_intersection = sum(intersection(:));
                        area_union = sum(union_area(:));

                        if area_union > 0
                            symmetry_score_array(i) = area_intersection / area_union;
                        else
                            symmetry_score_array(i) = 0;
                        end
                    else
                        symmetry_score_array(i) = 0;
                    end
                else
                    symmetry_score_array(i) = 0;
                end

                %% ====== 存储可视化数据 ======
                stored_data(i).img_gray = img_gray;
                stored_data(i).boundary = boundary;
                stored_data(i).centroids_reg = centroids_reg;
                stored_data(i).x_rot = x_rot;
                stored_data(i).z_rot = z_rot;
                stored_data(i).r_f = r_f;
                stored_data(i).z_f = z_f;
                stored_data(i).frame = t;

            catch
                is_valid(i) = false;
            end
        end

        %% ====== 存储到总结构体（不筛选，保留全部） ======
        AllResults(id).ID = id;
        AllResults(id).Frames = frames;
        AllResults(id).Centroids = centroids_track;
        AllResults(id).MajorAxisLength = majorAxisLength;
        AllResults(id).Volume_um3 = volumes_px * pixel_size^3;
        AllResults(id).Surface_um2 = surfaces_px * pixel_size^2;
        AllResults(id).Nu = nu_array;
        AllResults(id).M_tilde = M_tilde_array;
        AllResults(id).I_Gauss = I_K_array;
        AllResults(id).Rb = rb_array;
        AllResults(id).R_ve_um = R_ve_array * pixel_size;
        AllResults(id).StoredData = stored_data;
        AllResults(id).SymmetryScore = symmetry_score_array;
        AllResults(id).IsValid = is_valid;
        AllResults(id).meanIntensities_bg_C01 = meanIntensities_bg_C01;
        AllResults(id).meanIntensities_bg_C02 = meanIntensities_bg_C02;
        AllResults(id).meanIntensities_inner_C01 = meanIntensities_inner_C01;
        AllResults(id).meanIntensities_inner_C02 = meanIntensities_inner_C02;
        AllResults(id).meanIntensities_mem_C01 = meanIntensities_mem_C01;
        AllResults(id).meanIntensities_mem_C02 = meanIntensities_mem_C02;

        if Cfg.Verbose
            fprintf('有效帧 %d/%d\n', sum(is_valid), num_files);
        end
    end

    % -------- 关闭 reader --------
    try
        r.close();
    catch
    end

    % -------- 保存 --------
    if Cfg.SaveMAT
        save(fullfile(output_folder, 'AllResults.mat'), 'AllResults', '-v7.3');
        if Cfg.Verbose
            fprintf('[Compute] 保存完成：%s\n', fullfile(output_folder, 'AllResults.mat'));
        end
    end
end
