function TTracks = guvTrack_trackCentroids(files, distThresh_px, minTimeLength, MaxGap, opts)
% guvTrack_trackCentroids (Func_Track-style)
% ------------------------------------------------------------
% 核心追踪逻辑对齐 Func_Track：
%   PredPos = LastPos + dt * GlobalDrift                      
%   CostMat = pdist2(PredPos, CurrPos)                        
%   while min(CostMat) <= gate: greedy assign + inf row/col   
%   GlobalDrift = mean(shift of matched pairs)                
%
% 同时保留你的要求：
%   - 自动把 GUVData 的所有逐对象字段转移保存到轨迹（含 SymScore 等） 
%   - 字段名仍用 centroids（不再区分 centroids_px）
%   - 支持 MaxGap
%   - 可选：FFT 相位相关估漂移（仅当匹配对太少时作为备选）
%
% opts（可选）：
%   opts.StoreImg          = true/false   % 每条轨迹是否保存每帧整图 I 到 cell（很占内存）
%   opts.UseImageDrift     = true/false   % 是否启用相位相关（备选漂移）
%   opts.MinPairsForDrift  = 3            % >=该数量匹配对才用 match 漂移更新
%   opts.DriftAlpha        = 0            % EMA 平滑系数(0=不用平滑; 0.7=较平滑)
%   opts.MaxDriftStep      = distThresh_px% 漂移上限（防异常）
%   opts.DriftNoMatchMode  = 'keep'/'zero'% 无漂移来源时：保持上一帧/归零
%   opts.GateScaleWithDt   = true         % gate 是否按 dt 放大（建议 true）
%   opts.Debug             = false        % 打印日志
%   opts.UseShapeCost      = false        % 是否在 cost 中加入形态项（可提高密集场景鲁棒性）
%   opts.ShapeWeights      = [wL wA wS]   % majorAxisLength/Areas/SymScore 权重
%   opts.ShapeLambda       = 10           % 形态项总体倍率（cost = dist + lambda*shapeCost）

    if nargin < 2, error('需要 files 和 distThresh_px。'); end
    if nargin < 3 || isempty(minTimeLength), minTimeLength = 1; end
    if nargin < 4 || isempty(MaxGap), MaxGap = 0; end
    if nargin < 5, opts = struct(); end

    opts = guvUtil_setDefault(opts, 'StoreImg',         true);
    opts = guvUtil_setDefault(opts, 'UseImageDrift',    true);
    opts = guvUtil_setDefault(opts, 'MinPairsForDrift', 3);
    opts = guvUtil_setDefault(opts, 'DriftAlpha',       0);                % 默认更贴近 Func_Track：不做 EMA
    opts = guvUtil_setDefault(opts, 'MaxDriftStep',     distThresh_px);
    opts = guvUtil_setDefault(opts, 'DriftNoMatchMode', 'keep');           % gap 情况下 keep 往往比 zero 更稳
    opts = guvUtil_setDefault(opts, 'GateScaleWithDt',  true);
    opts = guvUtil_setDefault(opts, 'Debug',            false);

    % 图像读取回调（用于：每帧 MAT 不再保存整图时，仍可估计漂移/供调试）
    % 形式：I = opts.FrameGetter(t)
    opts = guvUtil_setDefault(opts, 'FrameGetter',       []);

    % ---------- 追踪质量诊断（区分：识别差 vs 追踪差） ----------
    % 记录每帧：
    %   nDet       : 本帧检测对象数量
    %   nMatchPrev : 与“上一帧活跃轨迹”成功匹配的数量（越低越可能是追踪gate/代价问题）
    %   meanIoU    : 匹配对的 IoU 均值（若启用 mask IoU；用于衡量分割一致性）
    %   nNew       : 新生轨迹数量（若异常偏大，多为识别碎片化/过分割）
    %   nActive    : 本帧匹配前的活跃轨迹数量
    % 若提供 opts.DiagOutDir，则额外保存：
    %   - TrackDiag_FrameStats.csv
    %   - TrackDiag_FrameStats.png（3条曲线：nDet / nMatchPrev / meanIoU）
    opts = guvUtil_setDefault(opts, 'SaveDiag', true);
    opts = guvUtil_setDefault(opts, 'DiagOutDir', '');
    opts = guvUtil_setDefault(opts, 'DiagTag', '');


    % 形态 cost（可选）
    opts = guvUtil_setDefault(opts, 'UseShapeCost', false);
    opts = guvUtil_setDefault(opts, 'ShapeWeights', [1, 1, 0.5]);           % [majorAxisLength, Areas, SymScore]
    opts = guvUtil_setDefault(opts, 'ShapeLambda',  10);

    % 方案A：mask/轮廓追踪（IoU cost，可与 distance 混合）
    % 依赖 GUVData.subMasks (cell) + GUVData.bboxes (Nx4)
    opts = guvUtil_setDefault(opts, 'UseMaskIoU', false);
    opts = guvUtil_setDefault(opts, 'IoUmin', 0.05);               % IoU 低于该值直接 gate 掉
    opts = guvUtil_setDefault(opts, 'IoULambda', 1.0);             % IoU cost 权重（以像素尺度计）
    opts = guvUtil_setDefault(opts, 'IoUUseFilledMask', true);     % 对膜环形 mask 先 fill holes 再算 IoU
    opts = guvUtil_setDefault(opts, 'MatchMethod', 'greedy');      % 'greedy' 或 'hungarian'（若有 matchpairs）

    nTimes = numel(files);
    if nTimes == 0
        TTracks = struct([]);
        return;
    end
    timeKeys = 1:nTimes;

    % ---- 读第 1 帧 ----
    S1 = load(fullfile(files(1).folder, files(1).name), 'GUVData');
    G1 = S1.GUVData;

    if ~isfield(G1, 'centroids')
        error('GUVData 中缺少 centroids 字段。');
    end

    imgFieldName  = 'I';
    sizeFieldName = 'imageSize';

    nObj1 = size(G1.centroids, 1);

    % ---- 诊断统计初始化（每帧一条）----
    diag_nDet       = nan(nTimes,1);
    diag_nMatchPrev = nan(nTimes,1);
    diag_meanIoU    = nan(nTimes,1);
    diag_nNew       = nan(nTimes,1);
    diag_nActive    = nan(nTimes,1);

    diag_nDet(1)       = nObj1;
    diag_nMatchPrev(1) = 0;
    diag_meanIoU(1)    = nan;
    diag_nNew(1)       = nObj1;
    diag_nActive(1)    = 0;

    % ---- 自动识别逐对象字段 ----
    objFields = guvTrack_inferObjFields(G1, nObj1, imgFieldName, sizeFieldName);
    if ~any(strcmp(objFields,'centroids'))
        objFields = [{'centroids'}, objFields];
    end

    % ---- baseTrack 模板 ----
    baseTrack = struct();
    baseTrack.ID       = [];
    baseTrack.frames   = [];
    baseTrack.gapCount = 0;
    baseTrack.isActive = true;

    if isfield(G1, sizeFieldName)
        baseTrack.(sizeFieldName) = G1.(sizeFieldName);
    else
        baseTrack.(sizeFieldName) = size(guvUtil_getFieldOr(G1, imgFieldName, []));
    end

    baseTrack.(imgFieldName) = {};

    % 保存每帧边界（来自 GUVData.boundaries{obj}，与 frames 同步追加）
    baseTrack.boundaries = {};


    for k = 1:numel(objFields)
        baseTrack.(objFields{k}) = [];
    end

    % ---- 初始化 TTracks（第 1 帧：每个对象一条轨迹）----
    TTracks = repmat(baseTrack, 1, 0);
    ImgPrev = guvUtil_getFieldOr(G1, imgFieldName, []);
    if isempty(ImgPrev) && ~isempty(opts.FrameGetter)
        try
            ImgPrev = opts.FrameGetter(timeKeys(1));
        catch
            ImgPrev = [];
        end
    end

    for oi = 1:nObj1
        tid = numel(TTracks) + 1;
        trk = baseTrack;
        trk.ID = tid;
        trk.frames = timeKeys(1);
        trk.gapCount = 0;
        trk.isActive = true;

        trk = guvTrack_setObjFieldsForOneObs(trk, G1, oi, objFields);

        % boundaries：直接从检测结果传递（不做后处理二次遍历）
        if isfield(G1,'boundaries') && numel(G1.boundaries) >= oi
            trk.boundaries = {G1.boundaries{oi}};
        else
            trk.boundaries = {[]};
        end

        if opts.StoreImg
            trk.(imgFieldName) = {ImgPrev};
        end

        TTracks(tid) = trk; %#ok<AGROW>
    end

    % ---- GlobalDrift（每帧漂移 dx,dy）----
    globalDrift = [0, 0];

    % =====================================================================
    % 主循环：t=2..T
    % =====================================================================
    for tt = 2:nTimes
        S = load(fullfile(files(tt).folder, files(tt).name), 'GUVData');
        G = S.GUVData;
        timeKey = timeKeys(tt);

        centroids = guvUtil_getFieldOr(G, 'centroids', []);
        nObj = size(centroids, 1);

        % 诊断：本帧检测数量
        diag_nDet(tt) = nObj;
        ImgCurr = guvUtil_getFieldOr(G, imgFieldName, []);
        if isempty(ImgCurr) && ~isempty(opts.FrameGetter)
            try
                ImgCurr = opts.FrameGetter(timeKey);
            catch
                ImgCurr = [];
            end
        end

        % ---- 动态扩展字段（如果本帧 GUVData 新增了逐对象字段）----
        [objFields, baseTrack, TTracks] = guvTrack_expandNewObjFieldsIfNeeded(G, nObj, objFields, baseTrack, TTracks, imgFieldName, sizeFieldName);

        % ---- 当前帧没有检测到对象：只更新 gap，必要时漂移归零/保持 ----
        if nObj == 0
            % 诊断：无检测对象
            diag_nActive(tt)    = numel(find([TTracks.isActive]));
            diag_nMatchPrev(tt) = 0;
            diag_meanIoU(tt)    = nan;
            diag_nNew(tt)       = 0;

            % 所有 active 的 gapCount + 1
            for tid = 1:numel(TTracks)
                if TTracks(tid).isActive
                    TTracks(tid).gapCount = TTracks(tid).gapCount + 1;
                    if TTracks(tid).gapCount > MaxGap
                        TTracks(tid).isActive = false;
                    end
                end
            end

            ImgPrev = ImgCurr;
            continue;
        end

        % ---- 获取活跃轨迹索引 ----
        activeIDs = find([TTracks.isActive]);
        if isempty(activeIDs)
            % 诊断：上一帧无活跃轨迹，本帧全部新生
            diag_nActive(tt)    = 0;
            diag_nMatchPrev(tt) = 0;
            diag_meanIoU(tt)    = nan;
            diag_nNew(tt)       = nObj;

            % 全死：本帧全部新开
            for oi = 1:nObj
                newID = numel(TTracks) + 1;
                trk = baseTrack;
                trk.ID = newID;
                trk.frames = timeKey;
                trk.gapCount = 0;
                trk.isActive = true;

                trk = guvTrack_setObjFieldsForOneObs(trk, G, oi, objFields);
            % boundaries：新生轨迹直接继承本帧观测边界
            if isfield(G,'boundaries') && numel(G.boundaries) >= oi
                trk.boundaries = {G.boundaries{oi}};
            else
                trk.boundaries = {[]};
            end

                if opts.StoreImg, trk.(imgFieldName) = {ImgCurr}; end
                TTracks(newID) = trk; %#ok<AGROW>
            end
            ImgPrev = ImgCurr;
            continue;
        end

        % ---- 预测位置 PredPos = LastPos + dt*GlobalDrift（Func_Track 同款）----
        M = numel(activeIDs);
        % 诊断：匹配前活跃轨迹数
        diag_nActive(tt) = M;
        PredPos   = nan(M,2);
        LastPos   = nan(M,2);
        dtActive  = ones(M,1);
        lastFrame = zeros(M,1);

        for r = 1:M
            tid = activeIDs(r);
            lastFrame(r) = TTracks(tid).frames(end);
            dt = timeKey - lastFrame(r);
            dt = max(dt, 1);                 % 安全
            dtActive(r) = dt;

            lp = TTracks(tid).centroids(end,:);
            LastPos(r,:) = lp;
            PredPos(r,:) = lp + dt * globalDrift;
        end

        CurrPos = centroids; % Nx2

        % ---- 成本矩阵：距离（Func_Track）----
        CostMat = pdist2(PredPos, CurrPos);

        IoUMat = []; % 若启用 mask IoU，将在下面计算

        % ---- 方案A：mask IoU cost（可选）----
        % 说明：如果 GUVData 中存在 subMasks/bboxes，则可计算 IoU，增强形变/拥挤场景的关联稳健性。
        if opts.UseMaskIoU && isfield(G,'subMasks') && isfield(G,'bboxes') ...
                && any(strcmp(objFields,'subMasks')) && any(strcmp(objFields,'bboxes'))
            IoUMat = guvTrack_computeIoUMat(TTracks, activeIDs, G, objFields, dtActive, opts);
            maskGate = (IoUMat < opts.IoUmin);
            IoUCost = (1 - IoUMat) * (distThresh_px * opts.IoULambda);
            CostMat = CostMat + IoUCost;
            CostMat(maskGate) = inf;
        end

        % ---- gating：按 dt 放大（用于 MaxGap）----
        if opts.GateScaleWithDt
            for r = 1:M
                gate = distThresh_px * dtActive(r);
                CostMat(r, CostMat(r,:) > gate) = inf;
            end
        else
            CostMat(CostMat > distThresh_px) = inf;
        end

        % ---- 可选：形态 cost（用于高密度/交叉时减少误配）----
        % cost = dist + lambda * shapeCost
        if opts.UseShapeCost
            shapeCost = guvTrack_computeShapeCostMat(TTracks, activeIDs, G, objFields, dtActive);
            CostMat = CostMat + opts.ShapeLambda * shapeCost;
        end

        matchedObj = false(nObj,1);
        matchedTrack = false(M,1);

        ShiftSum = [0,0];
        MatchCount = 0;

        % 诊断：匹配对的 IoU（若启用）
        matchIoUs = [];

        % ---- 匹配：默认贪心；可选 Hungarian(matchpairs) ----
        useHungarian = strcmpi(opts.MatchMethod,'hungarian') && exist('matchpairs','file')==2;
        if useHungarian
            pairs = matchpairs(CostMat, inf);  % pairs: [row col]
            for k = 1:size(pairs,1)
                r = pairs(k,1); c = pairs(k,2);
                if ~isfinite(CostMat(r,c)), continue; end
                tid = activeIDs(r);

                if ~isempty(IoUMat)
                    matchIoUs(end+1,1) = IoUMat(r,c); %#ok<AGROW>
                end

                TTracks(tid).frames(end+1,1) = timeKey;
                TTracks(tid) = guvTrack_appendObjFieldsOneObs(TTracks(tid), G, c, objFields);
                % boundaries：与匹配到的观测同步追加
                if isfield(G,'boundaries') && numel(G.boundaries) >= c
                    TTracks(tid).boundaries{end+1,1} = G.boundaries{c};
                else
                    TTracks(tid).boundaries{end+1,1} = [];
                end
                if opts.StoreImg
                    TTracks(tid).(imgFieldName){end+1,1} = ImgCurr;
                end
                TTracks(tid).gapCount = 0;

                shift = (CurrPos(c,:) - LastPos(r,:)) / dtActive(r);
                ShiftSum = ShiftSum + shift;
                MatchCount = MatchCount + 1;

                matchedObj(c) = true;
                matchedTrack(r) = true;
            end
        else
            % ---- 贪心 while-min（严格对齐 Func_Track）----
            while true
                    [minC, linIdx] = min(CostMat(:));
                    if isempty(minC) || ~isfinite(minC)
                        break;
                    end

                    [r, c] = ind2sub(size(CostMat), linIdx);
                    tid = activeIDs(r);

                    if ~isempty(IoUMat)
                        matchIoUs(end+1,1) = IoUMat(r,c); %#ok<AGROW>
                    end

                    % 追加观测到轨迹
                    TTracks(tid).frames(end+1,1) = timeKey;
                    TTracks(tid) = guvTrack_appendObjFieldsOneObs(TTracks(tid), G, c, objFields);
                % boundaries：与匹配到的观测同步追加
                if isfield(G,'boundaries') && numel(G.boundaries) >= c
                    TTracks(tid).boundaries{end+1,1} = G.boundaries{c};
                else
                    TTracks(tid).boundaries{end+1,1} = [];
                end
                    if opts.StoreImg
                        TTracks(tid).(imgFieldName){end+1,1} = ImgCurr;
                    end
                    TTracks(tid).gapCount = 0;

                    shift = (CurrPos(c,:) - LastPos(r,:)) / dtActive(r);
                    ShiftSum = ShiftSum + shift;
                    MatchCount = MatchCount + 1;

                    matchedObj(c) = true;
                    matchedTrack(r) = true;

                    CostMat(r,:) = inf;
                    CostMat(:,c) = inf;
            end
        end

        % ---- 处理未匹配轨迹：gapCount++ 超过 MaxGap -> inactive ----
        for r = 1:M
            tid = activeIDs(r);
            if ~matchedTrack(r)
                TTracks(tid).gapCount = TTracks(tid).gapCount + 1;
                if TTracks(tid).gapCount > MaxGap
                    TTracks(tid).isActive = false;
                end
            end
        end

        % ---- 新生轨迹：本帧未匹配观测全部新开（Func_Track 同款思想）----
        newIdx = find(~matchedObj);
        for k = 1:numel(newIdx)
            oi = newIdx(k);
            newID = numel(TTracks) + 1;

            trk = baseTrack;
            trk.ID = newID;
            trk.frames = timeKey;
            trk.gapCount = 0;
            trk.isActive = true;

            trk = guvTrack_setObjFieldsForOneObs(trk, G, oi, objFields);
            if opts.StoreImg
                trk.(imgFieldName) = {ImgCurr};
            end

            TTracks(newID) = trk; %#ok<AGROW>
        end

        % 诊断：本帧匹配/新生统计
        diag_nMatchPrev(tt) = MatchCount;
        diag_nNew(tt)       = numel(newIdx);
        if ~isempty(matchIoUs)
            diag_meanIoU(tt) = mean(matchIoUs);
        else
            diag_meanIoU(tt) = nan;
        end

        % ---- 更新 GlobalDrift：优先用匹配均值（Func_Track），匹配不足则用相位相关备选 ----
        drift_now = [];

        if MatchCount >= opts.MinPairsForDrift
            drift_now = ShiftSum / MatchCount;                            % 
        elseif opts.UseImageDrift && ~isempty(ImgPrev) && ~isempty(ImgCurr)
            drift_now = guvTrack_estimateDriftPhaseCorr(ImgPrev, ImgCurr);
        else
            if strcmpi(opts.DriftNoMatchMode, 'zero')
                drift_now = [0,0];
            else
                drift_now = []; % keep
            end
        end

        if ~isempty(drift_now)
            drift_now = guvUtil_limitStep(drift_now, opts.MaxDriftStep);
            a = opts.DriftAlpha;
            globalDrift = a*globalDrift + (1-a)*drift_now;   % a=0 -> 完全等于 drift_now
        else
            % keep previous globalDrift
        end

        if opts.Debug
            fprintf('[t=%d] MatchCount=%d, GlobalDrift=[%.2f %.2f]\n', timeKey, MatchCount, globalDrift(1), globalDrift(2));
        end

        ImgPrev = ImgCurr;
    end

    % ---- 轨迹长度过滤（Func_Track 最终清理思想）  ----
    if minTimeLength > 1
        keep = arrayfun(@(x) numel(x.frames) >= minTimeLength, TTracks);
        TTracks = TTracks(keep);
        for i = 1:numel(TTracks), TTracks(i).ID = i; end
    end

    % ---- 保存追踪诊断表（用于区分识别 vs 追踪） ----
    if opts.SaveDiag && ~isempty(opts.DiagOutDir)
        try
            if ~exist(opts.DiagOutDir, 'dir'), mkdir(opts.DiagOutDir); end

            tt = (1:nTimes)';
            Tdiag = table(tt, diag_nDet, diag_nActive, diag_nMatchPrev, diag_nNew, diag_meanIoU, ...
                'VariableNames', {'T','nDet','nActive','nMatchPrev','nNew','meanIoU'});

            tag = char(opts.DiagTag);
            if isempty(tag), tag = 'TrackDiag'; end
            csvPath = fullfile(opts.DiagOutDir, sprintf('%s_FrameStats.csv', tag));
            writetable(Tdiag, csvPath);

            % 画一张快速判别图：nDet / nMatchPrev / meanIoU
            fig = figure('Visible','off');
            plot(Tdiag.T, Tdiag.nDet, '-'); hold on;
            plot(Tdiag.T, Tdiag.nMatchPrev, '-');
            plot(Tdiag.T, Tdiag.meanIoU, '-');
            xlabel('Frame (t)');
            ylabel('Value');
            legend({'nDet','nMatchPrev','meanIoU'}, 'Location','best');
            title(sprintf('%s frame stats', tag), 'Interpreter','none');
            pngPath = fullfile(opts.DiagOutDir, sprintf('%s_FrameStats.png', tag));
            saveas(fig, pngPath);
            close(fig);

            % 额外：匹配率（nMatchPrev/nDet）与新生率（nNew/nDet）
            fig = figure('Visible','off');
            matchRate = Tdiag.nMatchPrev ./ max(Tdiag.nDet, 1);
            newRate   = Tdiag.nNew ./ max(Tdiag.nDet, 1);
            plot(Tdiag.T, matchRate, '-'); hold on;
            plot(Tdiag.T, newRate, '-');
            ylim([0 1]);
            xlabel('Frame (t)');
            ylabel('Rate');
            legend({'matchRate','newRate'}, 'Location','best');
            title(sprintf('%s rates', tag), 'Interpreter','none');
            pngPath = fullfile(opts.DiagOutDir, sprintf('%s_Rates.png', tag));
            saveas(fig, pngPath);
            close(fig);

        catch ME
            warning('SaveDiag failed: %s', ME.message);
        end
    end
end

% =========================================================================
% helpers: infer/expand obj fields
% =========================================================================
