function TTracks = guvTrack_attachBoundariesFromFrameMats(frameMatFiles, TTracks, maxDist_px)
%GUVTRACK_ATTACHBOUNDARIESFROMFRAMEMATS 把每帧轮廓线(boundary)匹配并写入 TTracks
% =========================================================================
% 目标：在保存的 TTracks.mat 中同时保留“每帧每个GUV的轮廓线数据”。
%
% 数据来源：每帧文件 Time_XXXX_Data.mat 中变量 GUVData.boundaries（cell，每个对象一条闭合边界）
% 匹配规则：对每条轨迹的每个 frame，根据轨迹 centroids 与本帧所有 detections 质心做最近邻匹配，
%          仅当距离 <= maxDist_px 时写入。
%
% 输出：
%   TTracks(id).boundaries : 1xN cell，与 TTracks(id).frames 同长度。
%                           boundaries{k} 是该帧对应的 Nx2 (row,col) 像素坐标。

    if nargin < 3 || isempty(maxDist_px)
        maxDist_px = inf;
    end

    if isempty(TTracks) || isempty(frameMatFiles)
        return;
    end

    % 建立：frame -> 文件索引
    nF = numel(frameMatFiles);
    fnum = zeros(nF,1);
    for i = 1:nF
        tok = regexp(frameMatFiles(i).name, 'Time_(\d+)_Data\.mat', 'tokens', 'once');
        if ~isempty(tok)
            fnum(i) = str2double(tok{1});
        else
            % 兜底：按排序序号
            fnum(i) = i;
        end
    end
    [fnum, order] = sort(fnum);
    frameMatFiles = frameMatFiles(order);

    % 为每条轨迹初始化 boundaries
    for id = 1:numel(TTracks)
        if ~isfield(TTracks(id),'frames') || isempty(TTracks(id).frames)
            continue;
        end
        TTracks(id).boundaries = cell(numel(TTracks(id).frames),1);
    end

    % 遍历每帧，加载 GUVData，做匹配
    for i = 1:nF
        matPath = fullfile(frameMatFiles(i).folder, frameMatFiles(i).name);
        S = load(matPath, 'GUVData');
        if ~isfield(S,'GUVData')
            continue;
        end
        GUVData = S.GUVData;
        if ~isfield(GUVData,'centroids') || ~isfield(GUVData,'boundaries')
            continue;
        end
        detC = GUVData.centroids;
        detB = GUVData.boundaries;
        if isempty(detC) || isempty(detB)
            continue;
        end

        % 当前帧号（与 track.frames 同一坐标系：脚本里 t 从 1 开始保存）
        t = fnum(i);

        % 针对每条轨迹：若包含该帧，则匹配
        for id = 1:numel(TTracks)
            if ~isfield(TTracks(id),'frames') || isempty(TTracks(id).frames)
                continue;
            end
            idx = find(TTracks(id).frames == t, 1, 'first');
            if isempty(idx)
                continue;
            end
            if ~isfield(TTracks(id),'centroids') || size(TTracks(id).centroids,1) < idx
                continue;
            end
            c = TTracks(id).centroids(idx,:);

            % 最近邻匹配 detection
            d2 = (detC(:,1)-c(1)).^2 + (detC(:,2)-c(2)).^2;
            [dmin2, j] = min(d2);
            if isempty(j)
                continue;
            end
            if sqrt(dmin2) <= maxDist_px
                if j <= numel(detB) && ~isempty(detB{j})
                    TTracks(id).boundaries{idx} = detB{j};
                end
            end
        end
    end
end
