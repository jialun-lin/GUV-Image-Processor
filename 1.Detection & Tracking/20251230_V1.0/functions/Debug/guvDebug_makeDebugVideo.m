function guvDebug_makeDebugVideo(files, TTracks, Cfg, SavePath, SeriesName, frameGetter)
%GUVMAKEDEBUGVIDEO 生成 HYS 风格的追踪叠加视频（用于快速 debug）
% 叠加内容：
%   - 底图：当前帧原图
%   - 轨迹：当前点 + ID + 尾迹（TailLen）
%
% 说明：
%   - 若每帧 MAT 中没有保存 GUVData.I，本函数会尝试用 frameGetter(t) 读取底图。

if nargin < 6, frameGetter = []; end

v = VideoWriter(SavePath, 'MPEG-4');
v.Quality = 100;
v.FrameRate = Cfg.Debug.VideoFPS;
open(v);

hFig = figure('Visible','off','Color','k','Position',[0 0 900 900]);
ax = axes('Parent',hFig,'Position',[0 0 1 1]);
Tail = 25; if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'TailLen'), Tail = Cfg.Debug.TailLen; end

% ---- outline options ----
showOutline = true;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'ShowOutline')
    showOutline = logical(Cfg.Debug.ShowOutline);
end
outlineColor = 'g';
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'OutlineColor')
    outlineColor = Cfg.Debug.OutlineColor;
end
outlineLW = 1.2;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'OutlineLineWidth')
    outlineLW = Cfg.Debug.OutlineLineWidth;
end

% ---- memBand outline options ----
showMemBand = false;
if isfield(Cfg,'Debug') && isfield(Cfg.Debug,'ShowMemBand')
    showMemBand = logical(Cfg.Debug.ShowMemBand);
end

for t = 1:numel(files)
    S = load(fullfile(files(t).folder, files(t).name));

    % -------- 取底图（优先从 MAT，缺失则从 FrameStore）--------
    imgShow = [];
    if isfield(S,'GUVData') && isfield(S.GUVData,'I') && ~isempty(S.GUVData.I)
        imgShow = S.GUVData.I;
    elseif ~isempty(frameGetter)
        try
            imgShow = frameGetter(t);
        catch
            imgShow = [];
        end
    end
    if isempty(imgShow)
        % 若底图无法获取（例如未保存FrameStore/Img），仍写入一帧黑底，避免生成空视频报错
        if isfield(S,'GUVData') && isfield(S.GUVData,'imageSize') && numel(S.GUVData.imageSize)==2
            H = S.GUVData.imageSize(1); W = S.GUVData.imageSize(2);
            imgShow = zeros(H, W, 'uint16');
        else
            imgShow = zeros(512, 512, 'uint16');
        end
    end

    imshow(imgShow, [], 'Parent', ax); hold(ax, 'on');

    % -------- 轮廓描边（所有当前帧检测到的 GUV）--------
    % 说明：轮廓来自 detectGUVRegions 输出的 GUVData.boundaries（全图坐标），
    %       能覆盖非圆形（椭球、哑铃、蛇形等）的外形。
    if showOutline && isfield(S,'GUVData') && isfield(S.GUVData,'boundaries') && ~isempty(S.GUVData.boundaries)
        Bd = S.GUVData.boundaries;
        for b = 1:numel(Bd)
            if isempty(Bd{b}), continue; end
            xyB = Bd{b};
            plot(ax, xyB(:,1), xyB(:,2), '-', 'Color', outlineColor, 'LineWidth', outlineLW);
        end
    end

    % -------- memBand 轮廓（用于检查环带厚度）--------
    if showMemBand && isfield(S,'GUVData') && isfield(S.GUVData,'memBandMasks') && isfield(S.GUVData,'bboxes')
        localPlotLocalMaskBoundaries(ax, S.GUVData.memBandMasks, S.GUVData.bboxes, 'r', outlineLW);
    end

    % -------- 轨迹叠加 --------
    for k = 1:numel(TTracks)
        idx = find(TTracks(k).frames == t, 1, 'last');
        if isempty(idx), continue; end

        xy = TTracks(k).centroids(idx,:);
        plot(ax, xy(1), xy(2), 'r+', 'MarkerSize', 6, 'LineWidth', 1);
        text(ax, xy(1)+5, xy(2), sprintf('%d', TTracks(k).ID), 'Color','y','FontSize',10);

        s0 = max(1, idx-Tail);
        tailXY = TTracks(k).centroids(s0:idx,:);
        plot(ax, tailXY(:,1), tailXY(:,2), 'y-', 'LineWidth', 1);
    end

    text(ax, 20, 30, sprintf('%s | T=%d', SeriesName, t), 'Color','w','FontSize',14);
    hold(ax, 'off');

    writeVideo(v, getframe(hFig));
end

close(v);
close(hFig);
end

function localPlotLocalMaskBoundaries(ax, maskList, bboxes, colorChar, lw)
%LOCALPLOTLOCALMASKBOUNDARIES 绘制局部mask的全局轮廓（用于memBand等）
% maskList{k}: ROI内逻辑mask; bboxes(k,:)=[x y w h]
if isempty(maskList) || isempty(bboxes)
    return;
end
n = min(numel(maskList), size(bboxes,1));
for k = 1:n
    mk = maskList{k};
    if isempty(mk) || ~any(mk(:)), continue; end
    bb = bboxes(k,:); % [x y w h]
    try
        B = bwboundaries(mk);
    catch
        continue;
    end
    for b = 1:numel(B)
        rc = B{b};
        if isempty(rc), continue; end
        x = rc(:,2) + bb(1) - 1;
        y = rc(:,1) + bb(2) - 1;
        plot(ax, x, y, '-', 'Color', colorChar, 'LineWidth', lw);
    end
end
end
