function IoUMat = guvTrack_computeIoUMat(TTracks, activeIDs, G, objFields, dtActive, opts)
    % 返回 MxN 的 IoU (0~1)。如果无法计算则为 0。
    M = numel(activeIDs);
    N = size(G.centroids,1);
    IoUMat = zeros(M,N);

    if ~isfield(G,'subMasks') || ~isfield(G,'bboxes')
        return;
    end

    for r = 1:M
        tid = activeIDs(r);
        if ~isfield(TTracks(tid),'subMasks') || isempty(TTracks(tid).subMasks)
            continue;
        end
        if ~isfield(TTracks(tid),'bboxes') || isempty(TTracks(tid).bboxes)
            continue;
        end
        % 取轨迹最后一次观测的 mask/bbox
        bb1 = TTracks(tid).bboxes(end,:);
        m1  = TTracks(tid).subMasks{end};
        if isempty(m1)
            continue;
        end
        if opts.IoUUseFilledMask
            m1 = imfill(logical(m1), 'holes');
        else
            m1 = logical(m1);
        end

        for c = 1:N
            bb2 = G.bboxes(c,:);
            m2  = G.subMasks{c};
            if isempty(m2)
                IoUMat(r,c) = 0;
                continue;
            end
            if opts.IoUUseFilledMask
                m2 = imfill(logical(m2), 'holes');
            else
                m2 = logical(m2);
            end
            IoUMat(r,c) = guvUtil_iouFromBBoxSubMask(bb1, m1, bb2, m2);
        end

        % gap 越大，对 IoU 的要求越“温和”一点（避免小形变 + gap 后续不上）
        % 这里不直接改 IoU 值，只是给出 hook：你后续若想按 dt 做门限，可在主函数里实现
        %#ok<NASGU>
        dt = dtActive(r);
    end
end

