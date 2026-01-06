function shapeCost = guvTrack_computeShapeCostMat(TTracks, activeIDs, G, objFields, dtActive)
    % 默认用 majorAxisLength / Areas / SymScore（存在才用）
    haveL = isfield(G,'majorAxisLength') && any(strcmp(objFields,'majorAxisLength'));
    haveA = isfield(G,'Areas')           && any(strcmp(objFields,'Areas'));
    haveS = isfield(G,'SymScore')        && any(strcmp(objFields,'SymScore'));

    M = numel(activeIDs);
    nObj = size(G.centroids,1);
    shapeCost = zeros(M, nObj);

    % 取观测值
    if haveL, Lobs = G.majorAxisLength; else, Lobs = []; end
    if haveA, Aobs = G.Areas; else, Aobs = []; end
    if haveS, Sobs = G.SymScore; else, Sobs = []; end

    for r = 1:M
        tid = activeIDs(r);

        % 取轨迹最后一帧形态
        cL = []; cA = []; cS = [];
        if haveL && ~isempty(TTracks(tid).majorAxisLength)
            cL = TTracks(tid).majorAxisLength(end,:);
        end
        if haveA && ~isempty(TTracks(tid).Areas)
            cA = TTracks(tid).Areas(end,:);
        end
        if haveS && ~isempty(TTracks(tid).SymScore)
            cS = TTracks(tid).SymScore(end,:);
        end

        sc = zeros(1, nObj);

        % majorAxisLength：用 log 比值（尺度不敏感）
        if haveL && ~isempty(cL)
            sc = sc + abs(log((Lobs(:)'+eps) ./ (cL+eps)));
        end

        % Areas：log 比值
        if haveA && ~isempty(cA)
            sc = sc + abs(log((Aobs(:)'+eps) ./ (cA+eps)));
        end

        % SymScore：绝对差（0~1）
        if haveS && ~isempty(cS)
            sc = sc + abs(Sobs(:)' - cS);
        end

        % gap 时稍微放宽形态项影响（避免 gap 后形态变化导致续不上）
        sc = sc / max(dtActive(r), 1);

        shapeCost(r,:) = sc;
    end
end

% =========================================================================
% 方案A：mask IoU cost
% =========================================================================
