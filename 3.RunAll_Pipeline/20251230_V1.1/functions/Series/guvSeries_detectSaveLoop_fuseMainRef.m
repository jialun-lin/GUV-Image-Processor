function guvSeries_detectSaveLoop_fuseMainRef(r, dims, Cfg, Paths, Thr, DetectOpts, Info, FrameStoreInfo, IsDebug)
%GUVSERIES_DETECTSAVELOOP_FUSEMAINREF
% -------------------------------------------------------------------------
% 本函数是“从开始到追踪结束”中最关键、也最容易出错的一段：
%   逐帧读图 → 每通道检测 → 同帧双通道融合(选主ref mask) → 用主ref mask测所有通道强度 → 保存每帧 MAT
%
% 你最终确认的核心规则（再次强调）：
%   (1) 每个通道都可以产生自己的对象mask；当两通道都检测到同一对象时，取 imfill 后面积更大者为主ref mask。
%   (2) 所有通道的强度（inner/mem/bg）都统一用“主ref mask”去测量（避免强度定义被 CType 混淆）。
%   (3) Cfg.Read.CType 只决定“如何从原图构造 innerMask/bgMask/memMask”，不决定强度含义。
%
% 输入：
%   r,dims,Cfg,Paths,Thr,DetectOpts,Info : 由 Pipeline/Series 初始化得到
% 输出：
%   - Paths.OutFrames 下生成 Time_XXXX_Data.mat （变量名固定为 GUVData，保持旧版一致）
%   - 可选生成 Debug/FramesPNG 下的逐帧 PNG（单XY调试用）
%   - 可选记录 FuseLog（同帧配对/来源统计）

T = dims.T;
CList  = Info.CList;
CType  = Info.CType;

nC = numel(CList);
if nC < 1
    error('Cfg.Read.CList 为空：没有可读取的通道。');
end

% 双通道融合参数（像素）
fuseDist_px = Thr.fuseDist_px; % 同帧配对距离阈值（像素）
useIoU = false; minIoU = 0.0;
if isfield(Cfg,'Fuse') && isfield(Cfg.Fuse,'Pair')
    if isfield(Cfg.Fuse.Pair,'UseIoU'), useIoU = logical(Cfg.Fuse.Pair.UseIoU); end
    if isfield(Cfg.Fuse.Pair,'MinIoU'), minIoU = double(Cfg.Fuse.Pair.MinIoU); end
end

FuseLogAll = cell(T,1);

% 用于后处理分割的“前一帧参照”（按通道存，保持原逻辑不变）
prevDet = cell(nC,1);

for t = 1:T
    % -------------------- 读本帧所有通道图像 --------------------
    Icell = cell(nC,1);
    for cc = 1:nC
        c = CList(cc);
        Icell{cc} = bfGetPlaneAtZCT(r, Cfg.Read.Z, c, t);
    end

    % -------------------- FrameStore（视频导出用；默认只存一个显示通道） --------------------
    if ~isempty(FrameStoreInfo)
        % (1) /I：默认存 Cfg.Read.RefC（用于 debug/兼容旧逻辑）
        refIdx = find(CList==Cfg.Read.RefC, 1, 'first');
        if isempty(refIdx), refIdx = 1; end
        guvIO_frameStoreWriteFrameH5(FrameStoreInfo.h5Path, Icell{refIdx}, t, '/I');

        % (2) /I_Cxx：若 FrameStoreMode='multi'，则额外保存每个通道
        if isfield(FrameStoreInfo,'Mode') && strcmpi(FrameStoreInfo.Mode,'multi')
            for cc = 1:nC
                ds = sprintf('/I_C%02d', CList(cc));
                guvIO_frameStoreWriteFrameH5(FrameStoreInfo.h5Path, Icell{cc}, t, ds);
            end
        end
    end

    % -------------------- 每通道独立检测 --------------------
    detC = cell(nC,1);
    figDet = []; %#ok<NASGU>
    for cc = 1:nC
        I = Icell{cc};
        ctype = CType{cc};

        [det, fig] = guvDetect_runFrame(I, ctype, Thr.minMajor_px, Thr.maxMajor_px, DetectOpts);

        % （可选）后处理分割：对每个通道独立执行，避免“每个对象refFromC不同”导致无法选择图像
        if isfield(Cfg,'Post') && isfield(Cfg.Post,'Watershed') && Cfg.Post.Watershed.Enable
            try
                det = guvDetect_postSplitByCoverageWatershed(I, det, prevDet{cc}, Cfg, DetectOpts);
            catch ME
                warning('[%s] postSplit failed at t=%d C=%d: %s', Paths.SeriesName, t, CList(cc), ME.message);
            end
        end

        det = guvMatch_annotateChannelFluor(det, CList(cc)); % 写入本通道自身字段（便于debug/对照）
        detC{cc} = det;
        prevDet{cc} = det;

        % 逐帧PNG通常只保存融合后的图，因此这里不保存 det fig
        if ~isempty(fig) && isvalid(fig), close(fig); end
    end

    % -------------------- 同帧融合（当前实现：仅支持 1 或 2 通道） --------------------
    if nC == 1
        % 单通道：主ref就是自身
        GUVData = detC{1};
        FuseLog = struct('mode','single','n', guvUtil_countObjects(GUVData));
    elseif nC == 2
        c1 = CList(1); c2 = CList(2);
        optsFuse = struct('UseIoU', useIoU, 'MinIoU', minIoU);
        [GUVData, FuseLog] = guvFuse_twoChannel_mainRef(detC{1}, detC{2}, c1, c2, fuseDist_px, optsFuse);
    else
        % 多于2通道：为了避免隐藏错误，先给出明确警告并退化为“第一个通道为主ref”
        warning('当前实现主要面向2通道；检测到 %d 通道，将退化为：使用第一个通道作为主ref。', nC);
        GUVData = detC{1};
        FuseLog = struct('mode','fallback_first_channel','n', guvUtil_countObjects(GUVData));
    end

    % -------------------- 排序（可选）：按 y,x 排序，使输出更稳定、便于debug --------------------
    if isfield(GUVData,'centroids') && ~isempty(GUVData.centroids)
        [~,ord] = sortrows(GUVData.centroids, [2 1]);
        GUVData = guvUtil_takeRows(GUVData, ord);
        % 同步对 refFromC / srcIdx_Cxx 等逐对象字段（guvUtil_takeRows 已处理）
    end

    % -------------------- 用主ref masks 测量所有通道强度 --------------------
    % 这里用现成的 guvMatch_measureChannelOnRefMasks：
    %   - inner/mem 都在 GUVData.subMasks / GUVData.memBandMasks 上测
    %   - bgMean 可按各通道 CType 独立估计
    for cc = 1:nC
        c = CList(cc);
        ctype = CType{cc};
        I = Icell{cc};
        GUVData = guvMatch_measureChannelOnRefMasks(GUVData, I, c, ctype, Cfg, DetectOpts);
    end

    % 为兼容旧字段：meanIntensities / meanIntensities_mem / bgMeanIntensity 取“显示通道（Cfg.Read.RefC）”的值
    refC = Cfg.Read.RefC;
    fnInner = sprintf('meanIntensities_inner_C%02d', refC);
    fnMem   = sprintf('meanIntensities_mem_C%02d',   refC);
    fnBg    = sprintf('meanIntensities_bg_C%02d',    refC);
    if isfield(GUVData, fnInner), GUVData.meanIntensities = GUVData.(fnInner); end
    if isfield(GUVData, fnMem),   GUVData.meanIntensities_mem = GUVData.(fnMem); end
    if isfield(GUVData, fnBg) && ~isempty(GUVData.(fnBg))
        GUVData.bgMeanIntensity = GUVData.(fnBg)(1);
    end

    % 统一补充元信息（保持旧版字段存在）
    if Cfg.Output.SaveImgInFrameMAT
        % 为避免体积爆炸，仅保存一个显示通道（RefC）的图像
        refIdx = find(CList==refC, 1, 'first');
        if isempty(refIdx), refIdx = 1; end
        GUVData.I = Icell{refIdx};
    else
        GUVData.I = [];
    end
    GUVData.imageSize = [dims.H, dims.W];

    % -------------------- 保存 per-frame MAT --------------------
    if Cfg.Output.SavePerFrameMAT
        matFile = fullfile(Paths.OutFrames, sprintf('Time_%04d_Data.mat', t));
        save(matFile, 'GUVData', '-v7');
    end

    % -------------------- Debug：保存逐帧PNG + 记录FuseLog --------------------
    if IsDebug && Cfg.Debug.SaveFramePNG
        try
            fig = guvDebug_makeFrameFigureFuse(Icell, CList, Info.CNames, detC, GUVData, FuseLog, Cfg);
            pngFile = fullfile(Paths.OutDebug, sprintf('Time_%04d.png', t));
            exportgraphics(fig, pngFile);
            close(fig);
        catch ME
            warning('[%s] Debug frame png failed at t=%d: %s', Paths.SeriesName, t, ME.message);
        end
    end

    FuseLogAll{t} = FuseLog;

    if mod(t,20)==0 || t==T
        fprintf('  [%s] Detect+Fuse frame %d/%d\n', Paths.SeriesName, t, T);
    end
end

% -------------------- 保存FuseLog汇总（单XY调试特别有用） --------------------
if IsDebug && Cfg.Debug.SaveFuseLog
    try
        outMat = fullfile(Paths.OutDebug, 'FuseLog_AllFrames.mat');
        save(outMat, 'FuseLogAll', '-v7');
    catch
    end
end

end