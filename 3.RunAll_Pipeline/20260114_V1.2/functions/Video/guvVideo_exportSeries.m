function outFiles = guvVideo_exportSeries(seriesFolder, Cfg, SeriesID, prefix)
%GUVVIDEO_EXPORTSERIES  基于 FrameStore/ND2 导出单个 XY 的视频（C1/C2/Merge）
% -------------------------------------------------------------------------
% 输入：
%   seriesFolder - 单个 XY 输出目录（例如 OutRoot/XY001）
%   Cfg          - 配置结构体（来自 guvPipeline_configDefault + JSON 覆盖）
%   SeriesID     - 数字编号（用于命名；可为空）
%   prefix       - SeriesPrefix（默认 'XY'）
%
% 输出：
%   outFiles - 生成的视频文件路径 cellstr

if nargin < 4 || isempty(prefix)
    prefix = 'XY';
end

outFiles = {};

if ~exist(seriesFolder,'dir')
    error('Series folder not found: %s', seriesFolder);
end

% -------------------- 通道信息：C1/C2 定义为 Cfg.Read.CList(1/2) --------------------
Info = guvPipeline_getChannelInfo(Cfg);
CList = Info.CList;
if isempty(CList)
    error('Cfg.Read.CList 为空，无法导出视频。');
end

c1 = CList(1);
c2 = [];
if numel(CList) >= 2
    c2 = CList(2);
end

% -------------------- 读帧器：优先 FrameStore.h5；必要时回退 ND2 --------------------
h5Path = fullfile(seriesFolder, Cfg.Output.FrameStoreName);
useH5 = exist(h5Path,'file')==2;

% 图像尺寸/帧数
[H,W,T] = localGetHWT(seriesFolder, h5Path, useH5);

% 获取每个通道的读帧函数（uint16 2D）
getC1 = [];
getC2 = [];

if useH5
    getC1 = localBuildH5Getter(h5Path, c1, Cfg, true);
    if ~isempty(c2)
        getC2 = localBuildH5Getter(h5Path, c2, Cfg, false);
    end
end

needC1 = localNeedTask(Cfg.Video.Tasks, "C1") || localNeedTask(Cfg.Video.Tasks, "MERGE");
needC2 = localNeedTask(Cfg.Video.Tasks, "C2") || localNeedTask(Cfg.Video.Tasks, "MERGE");

% 若缺通道 getter，则回退 ND2（除非 UseFrameStoreOnly=true）
nd2Reader = [];
if (needC1 && isempty(getC1)) || (needC2 && ~isempty(c2) && isempty(getC2))
    if isfield(Cfg.Video,'UseFrameStoreOnly') && Cfg.Video.UseFrameStoreOnly
        error('FrameStore 缺失所需通道数据集且 UseFrameStoreOnly=true。请将 Cfg.Output.FrameStoreMode 设为 ''multi'' 或允许回读 ND2。');
    end
    if ~isfield(Cfg,'ND2Path') || isempty(Cfg.ND2Path) || exist(Cfg.ND2Path,'file')~=2
        error('需要回读 ND2 以导出视频，但 Cfg.ND2Path 不可用。');
    end
    [getC1, getC2, nd2Reader] = localBuildNd2Getters(Cfg.ND2Path, SeriesID, Cfg, c1, c2);
end

% -------------------- 自动对比度（若用户未显式指定） --------------------
mm1 = [];
mm2 = [];
if isfield(Cfg.Video,'Contrast')
    if isfield(Cfg.Video.Contrast,'C1'), mm1 = Cfg.Video.Contrast.C1; end
    if isfield(Cfg.Video.Contrast,'C2'), mm2 = Cfg.Video.Contrast.C2; end
end

if isempty(mm1) && ~isempty(getC1)
    mm1 = localAutoMinMax(getC1, T);
end
if isempty(mm2) && ~isempty(getC2)
    mm2 = localAutoMinMax(getC2, T);
end

% -------------------- 伪色 --------------------
col1 = [1 1 1];
col2 = [1 1 1];
if isfield(Cfg.Video,'Color')
    if isfield(Cfg.Video.Color,'C1'), col1 = double(Cfg.Video.Color.C1(:)'); end
    if isfield(Cfg.Video.Color,'C2'), col2 = double(Cfg.Video.Color.C2(:)'); end
end
col1 = localClamp01(col1);
col2 = localClamp01(col2);

% -------------------- 输出目录与 VideoWriter --------------------
subdir = 'Video';
if isfield(Cfg.Video,'OutputSubdir') && ~isempty(Cfg.Video.OutputSubdir)
    subdir = char(Cfg.Video.OutputSubdir);
end
outDir = fullfile(seriesFolder, subdir);
if ~exist(outDir,'dir'), mkdir(outDir); end

fmt = 'mp4';
if isfield(Cfg.Video,'Format') && ~isempty(Cfg.Video.Format)
    fmt = lower(char(Cfg.Video.Format));
end
fps = 10;
if isfield(Cfg.Video,'FPS') && ~isempty(Cfg.Video.FPS)
    fps = double(Cfg.Video.FPS);
end
q = 90;
if isfield(Cfg.Video,'Quality') && ~isempty(Cfg.Video.Quality)
    q = double(Cfg.Video.Quality);
end

tasks = string(Cfg.Video.Tasks);
tasks = upper(tasks);

writers = struct();
taskList = {};
for i = 1:numel(tasks)
    tk = char(tasks(i));
    if strcmpi(tk,'MERGE') && isempty(c2)
        warning('[%s%03d] Skip MERGE: only 1 channel.', prefix, SeriesID);
        continue;
    end
    if strcmpi(tk,'C2') && isempty(c2)
        warning('[%s%03d] Skip C2: only 1 channel.', prefix, SeriesID);
        continue;
    end

    outName = sprintf('%s%03d_%s.%s', prefix, SeriesID, tk, fmt);
    outPath = fullfile(outDir, outName);
    vw = localMakeVideoWriter(outPath, fmt, fps, q);
    open(vw);
    writers.(tk) = vw;
    taskList{end+1} = tk; %#ok<AGROW>
    outFiles{end+1,1} = outPath; %#ok<AGROW>
end

if isempty(taskList)
    return;
end

% -------------------- 渲染窗口（无工具箱依赖：imshow + getframe） --------------------
[fig, ax, hImg, hTs, hSbLabel] = localInitFigure(W, H, Cfg);

% 静态 scalebar 绘制
localDrawScaleBar(ax, W, H, Cfg);
if isgraphics(hSbLabel)
    % label 已由 localDrawScaleBar 内创建；这里只是占位
end

% -------------------- 主循环：每帧读图 → 生成 RGB → 写视频 --------------------
for t = 1:T
    I1 = [];
    I2 = [];
    if needC1
        I1 = getC1(t);
    end
    if needC2 && ~isempty(c2)
        I2 = getC2(t);
    end

    % 时间戳文本
    if isgraphics(hTs)
        hTs.String = localMakeTimeString(t, Cfg);
    end

    for kk = 1:numel(taskList)
        tk = taskList{kk};
        switch upper(tk)
            case 'C1'
                rgb = localMakePseudoRGB(I1, mm1, col1, H, W);
            case 'C2'
                rgb = localMakePseudoRGB(I2, mm2, col2, H, W);
            case 'MERGE'
                rgb1 = localMakePseudoRGB(I1, mm1, col1, H, W);
                rgb2 = localMakePseudoRGB(I2, mm2, col2, H, W);
                rgb = min(1, rgb1 + rgb2);
            otherwise
                continue;
        end

        hImg.CData = rgb;
        drawnow limitrate;
        fr = getframe(ax);
        writeVideo(writers.(tk), fr);
    end
end

% -------------------- 清理 --------------------
close(fig);
for kk = 1:numel(taskList)
    tk = taskList{kk};
    try
        close(writers.(tk));
    catch
    end
end

% 关闭 ND2 reader（如果本次导出启用了回读）
try
    if ~isempty(nd2Reader)
        nd2Reader.close();
    end
catch
end

end

% =====================================================================
% Local utilities
% =====================================================================

function tf = localNeedTask(tasks, name)
tasks = upper(string(tasks));
tf = any(tasks == upper(string(name)));
end

function [H,W,T] = localGetHWT(seriesFolder, h5Path, useH5)
H = []; W = []; T = [];
infoMat = fullfile(seriesFolder, 'FrameStoreInfo.mat');
if exist(infoMat,'file')==2
    S = load(infoMat);
    if isfield(S,'FrameStoreInfo')
        if isfield(S.FrameStoreInfo,'H'), H = S.FrameStoreInfo.H; end
        if isfield(S.FrameStoreInfo,'W'), W = S.FrameStoreInfo.W; end
        if isfield(S.FrameStoreInfo,'T'), T = S.FrameStoreInfo.T; end
    end
end

if (isempty(H) || isempty(W) || isempty(T)) && useH5
    ii = h5info(h5Path, '/I');
    sz = ii.Dataspace.Size;
    H = sz(1); W = sz(2); T = sz(3);
end

if isempty(H) || isempty(W) || isempty(T)
    error('无法确定 H/W/T：缺少 FrameStoreInfo.mat 且 FrameStore.h5 不可用。');
end
end

function getF = localBuildH5Getter(h5Path, c, Cfg, isC1)
% 优先 /I_Cxx；若不存在且该通道为 RefC，则回退 /I
getF = [];
ds = sprintf('/I_C%02d', c);
try
    h5info(h5Path, ds);
    getF = @(t) guvIO_frameStoreReadFrameH5(h5Path, t, ds);
    return;
catch
end

% /I：仅当 c==RefC 时可用
if isfield(Cfg,'Read') && isfield(Cfg.Read,'RefC') && c == Cfg.Read.RefC
    try
        h5info(h5Path, '/I');
        getF = @(t) guvIO_frameStoreReadFrameH5(h5Path, t, '/I');
        return;
    catch
    end
end

% 若仍不可用，则返回空，让上层决定是否回读 ND2
if isC1
    getF = [];
else
    getF = [];
end
end

function [getC1, getC2, r] = localBuildNd2Getters(nd2Path, seriesID, Cfg, c1, c2)
% 使用 Bio-Formats reader 回读 ND2（仅视频导出，不需要跑检测）
r = bfGetReader(nd2Path);

% 若没有 seriesID（或不是正数），默认 1
if isempty(seriesID) || ~isfinite(seriesID) || seriesID < 1
    seriesID = 1;
end
try
    r.setSeries(seriesID-1);
catch
    % fallback：按目录名解析失败时，仍可用当前 series
end

getC1 = @(t) bfGetPlaneAtZCT(r, Cfg.Read.Z, c1, t);
getC2 = [];
if ~isempty(c2)
    getC2 = @(t) bfGetPlaneAtZCT(r, Cfg.Read.Z, c2, t);
end
end

function mm = localAutoMinMax(getF, T)
% 基于若干采样帧估计对比度范围
ns = min(12, T);
idx = unique(round(linspace(1, T, ns)));
vals = [];
for k = 1:numel(idx)
    I = double(getF(idx(k)));
    vals = [vals; I(:)]; %#ok<AGROW>
end
lo = prctile(vals, 1);
hi = prctile(vals, 99.8);
if hi <= lo
    hi = lo + 1;
end
mm = [lo hi];
end

function rgb = localMakePseudoRGB(I, mm, col, H, W)
if isempty(I)
    rgb = zeros(H,W,3,'double');
    return;
end
I = double(I);
lo = double(mm(1)); hi = double(mm(2));
S = (I - lo) ./ max(hi-lo, eps);
S = min(1, max(0, S));
rgb = cat(3, S*col(1), S*col(2), S*col(3));
end

function v = localMakeVideoWriter(outPath, fmt, fps, q)
fmt = lower(fmt);
switch fmt
    case 'mp4'
        v = VideoWriter(outPath, 'MPEG-4');
        v.Quality = max(0, min(100, q));
    case 'avi'
        v = VideoWriter(outPath, 'Motion JPEG AVI');
        v.Quality = max(0, min(100, q));
    otherwise
        error('Unsupported video format: %s', fmt);
end
v.FrameRate = fps;
end

function [fig, ax, hImg, hTs, hSbLabel] = localInitFigure(W, H, Cfg)
fig = figure('Visible','off', 'Color','k', 'Units','pixels', 'Position',[100 100 W H]);
ax = axes(fig, 'Units','normalized', 'Position',[0 0 1 1]);
axis(ax,'off');
set(ax,'XLim',[1 W],'YLim',[1 H]);
set(ax,'YDir','reverse');
hold(ax,'on');

hImg = imshow(zeros(H,W,3,'double'), 'Parent', ax);

hTs = gobjects(1);
if isfield(Cfg.Video,'TimeStamp') && isfield(Cfg.Video.TimeStamp,'Enable') && Cfg.Video.TimeStamp.Enable
    pos = [20 30];
    fs = 16;
    col = [1 1 1];
    if isfield(Cfg.Video.TimeStamp,'Position'), pos = double(Cfg.Video.TimeStamp.Position); end
    if isfield(Cfg.Video.TimeStamp,'FontSize'), fs = double(Cfg.Video.TimeStamp.FontSize); end
    if isfield(Cfg.Video.TimeStamp,'Color'), col = double(Cfg.Video.TimeStamp.Color); end
    col = localClamp01(col);
    hTs = text(ax, pos(1), pos(2), '', 'Color', col, 'FontSize', fs, 'FontWeight','bold', 'Interpreter','none');
end

hSbLabel = gobjects(1);
end

function localDrawScaleBar(ax, W, H, Cfg)
if ~isfield(Cfg.Video,'ScaleBar') || ~isfield(Cfg.Video.ScaleBar,'Enable') || ~Cfg.Video.ScaleBar.Enable
    return;
end
if ~isfield(Cfg,'PixelSize_um') || isempty(Cfg.PixelSize_um)
    return;
end

lenUm = 50;
thick = 6;
pos = []; % []=auto (bottom-right). Or [X Y] in pixels: [x_left, y_bottom] of the scale bar.
fs = 16;
col = [1 1 1];
if isfield(Cfg.Video.ScaleBar,'Length_um'), lenUm = double(Cfg.Video.ScaleBar.Length_um); end
if isfield(Cfg.Video.ScaleBar,'Thickness_px'), thick = double(Cfg.Video.ScaleBar.Thickness_px); end
if isfield(Cfg.Video.ScaleBar,'Position')
    p = Cfg.Video.ScaleBar.Position;
    if isstring(p) || ischar(p)
        pos = char(p);
    elseif isnumeric(p)
        pos = p;
    end
end
if isfield(Cfg.Video.ScaleBar,'FontSize'), fs = double(Cfg.Video.ScaleBar.FontSize); end
if isfield(Cfg.Video.ScaleBar,'Color'), col = double(Cfg.Video.ScaleBar.Color); end
col = localClamp01(col);

lenPx = max(1, round(lenUm / double(Cfg.PixelSize_um)));
margin = 20;

if isempty(pos)
    % Auto placement (bottom-right)
    x2 = W - margin; x1 = max(1, x2-lenPx);
    y2 = H - margin; y1 = y2 - thick;
    tx = x1; ty = y1 - 10;
elseif isnumeric(pos) && numel(pos) >= 2
    % Explicit pixel coordinates: [x_left, y_bottom] of the scale bar
    x1 = double(pos(1));
    y2 = double(pos(2));
    x1 = max(1, min(W, x1));
    y2 = max(1, min(H, y2));
    x2 = min(W, x1 + lenPx);
    y1 = max(1, y2 - thick);
    tx = x1; ty = y1 - 10;
else
    % Backward compatible: keyword positions like 'bottom-right'
    pstr = lower(char(pos));
    switch pstr
    case 'bottom-right'
        x2 = W - margin; x1 = max(1, x2-lenPx);
        y2 = H - margin; y1 = y2 - thick;
        tx = x1; ty = y1 - 10;
    case 'bottom-left'
        x1 = margin; x2 = min(W, x1+lenPx);
        y2 = H - margin; y1 = y2 - thick;
        tx = x1; ty = y1 - 10;
    case 'top-right'
        x2 = W - margin; x1 = max(1, x2-lenPx);
        y1 = margin; y2 = y1 + thick;
        tx = x1; ty = y2 + 10;
    case 'top-left'
        x1 = margin; x2 = min(W, x1+lenPx);
        y1 = margin; y2 = y1 + thick;
        tx = x1; ty = y2 + 10;
    otherwise
        x2 = W - margin; x1 = max(1, x2-lenPx);
        y2 = H - margin; y1 = y2 - thick;
        tx = x1; ty = y1 - 10;
    end
end

% --- Place label first, then ensure the bar is always below the label ---
labelStr = sprintf('%g um', lenUm);
gap = max(4, round(fs*0.35));

% Default: label above the bar (bar under text)
tx = x1;
ty = y1 - gap;

% Measure text extent (in data units; axes are pixel-aligned with YDir='reverse')
hTmp = text(ax, tx, ty, labelStr, 'Color', col, 'FontSize', fs, 'FontWeight','bold', ...
    'Interpreter','none', 'VerticalAlignment','bottom', 'HorizontalAlignment','left', ...
    'Visible','off');
ext = get(hTmp, 'Extent'); % [x y w h], y is lower edge in data units (pixel coords)
delete(hTmp);

% In YDir='reverse', the top edge is ext(2) - ext(4)
topEdgeY = ext(2) - ext(4);

% If label would go out of the top boundary, push the whole scalebar group down
shiftY = 0;
if topEdgeY < 1
    shiftY = (1 - topEdgeY) + 1; % +1 px buffer
    shiftY = min(shiftY, max(0, H - y2));
end

if shiftY ~= 0
    y1 = y1 + shiftY;
    y2 = y2 + shiftY;
    ty = ty + shiftY;
end

% Final clamp to image bounds (best-effort)
if y2 > H
    dy = y2 - H;
    y1 = max(1, y1 - dy);
    y2 = H;
    ty = max(1, ty - dy);
end

% Draw bar and label (bar always under text)
rectangle(ax, 'Position',[x1 y1 (x2-x1) thick], 'FaceColor', col, 'EdgeColor', col);
text(ax, tx, ty, labelStr, 'Color', col, 'FontSize', fs, 'FontWeight','bold', ...
    'Interpreter','none', 'VerticalAlignment','bottom', 'HorizontalAlignment','left');
end

function s = localMakeTimeString(t, Cfg)
if ~isfield(Cfg.Video,'TimeStamp') || ~isfield(Cfg.Video.TimeStamp,'Enable') || ~Cfg.Video.TimeStamp.Enable
    s = '';
    return;
end
st = 1;
dt = Cfg.FrameInterval_s;
unit = 's';
if isfield(Cfg.Video.TimeStamp,'StartFrame'), st = double(Cfg.Video.TimeStamp.StartFrame); end
if isfield(Cfg.Video.TimeStamp,'Interval_s') && ~isempty(Cfg.Video.TimeStamp.Interval_s)
    dt = double(Cfg.Video.TimeStamp.Interval_s);
end
if isfield(Cfg.Video.TimeStamp,'Unit') && ~isempty(Cfg.Video.TimeStamp.Unit)
    unit = char(Cfg.Video.TimeStamp.Unit);
end

tt = (double(t) - double(st)) * dt;
if tt < 0, tt = 0; end

switch lower(unit)
    case 'min'
        s = sprintf('t = %.2f min', tt/60);
    case 's'
        s = sprintf('t = %.1f s', tt);
    otherwise
        s = sprintf('t = %.1f %s', tt, unit);
end
end

function x = localClamp01(x)
x = double(x(:)');
if numel(x) ~= 3
    x = [1 1 1];
end
x = min(1, max(0, x));
end