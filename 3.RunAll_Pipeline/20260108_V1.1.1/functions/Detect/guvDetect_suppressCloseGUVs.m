function Data = guvDetect_suppressCloseGUVs(GUVData, distanceThresh)
    C = GUVData.centroids;
    N = size(C,1);
    visited = false(N,1);

    % fields to merge
    fn = fieldnames(GUVData);
    skip = {'I','imageSize'};
    % prepare new containers
    % 注意：GUVData 中包含 cell 字段（例如 boundaries），不能简单用 [] 初始化并忽略，
    % 否则会把轮廓信息“清空”。这里按字段类型做合适的初始化。
    out = struct();
    for i=1:numel(fn)
        name = fn{i};
        if any(strcmp(name, {'I','imageSize'}))
            % 后面单独赋值
            out.(name) = [];
        else
            v = GUVData.(name);
            if iscell(v)
                out.(name) = {};
            else
                out.(name) = [];
            end
        end
    end
    out.I = GUVData.I;
    out.imageSize = GUVData.imageSize;

    for i = 1:N
        if visited(i), continue; end

        d = sqrt(sum((C - C(i,:)).^2, 2));
        idxCluster = find(d <= distanceThresh & ~visited);
        visited(idxCluster) = true;

        % centroids
        out.centroids = [out.centroids; mean(GUVData.centroids(idxCluster,:), 1, 'omitnan')]; %#ok<AGROW>

        % pairs: keep representative (same as your old logic)
        % pairs 字段仅在旧版 inner-mem 合并时存在；新流程可能没有该字段
        if isfield(GUVData,'pairs')
            Pairs = GUVData.pairs;
            P_cluster = [0 0];
            for k = 1:numel(idxCluster)
                p = Pairs(idxCluster(k),:);
                if P_cluster(1) == 0 && p(1) ~= 0, P_cluster(1) = p(1); end
                if P_cluster(2) == 0 && p(2) ~= 0, P_cluster(2) = p(2); end
            end
            out.pairs = [out.pairs; P_cluster]; %#ok<AGROW>
        end
        for k = 1:numel(idxCluster)
        end

        % 选择一个“代表目标”用于继承非数值字段（如 boundaries）
        % 优先：FilledAreas 最大；若不存在则 Areas 最大；再不行就取 idxCluster(1)
        rep = idxCluster(1);
        if isfield(GUVData,'FilledAreas') && isnumeric(GUVData.FilledAreas) && size(GUVData.FilledAreas,1)==N
            [~, ii] = max(GUVData.FilledAreas(idxCluster), [], 'omitnan');
            rep = idxCluster(ii);
        elseif isfield(GUVData,'Areas') && isnumeric(GUVData.Areas) && size(GUVData.Areas,1)==N
            [~, ii] = max(GUVData.Areas(idxCluster), [], 'omitnan');
            rep = idxCluster(ii);
        end

        % other numeric fields: mean; SymScore: max
        for f = 1:numel(fn)
            name = fn{f};
            if any(strcmp(name, skip)) || strcmp(name,'centroids') || strcmp(name,'pairs')
                continue;
            end

            val = GUVData.(name);

            if isnumeric(val) && size(val,1) == N
                vcl = val(idxCluster,:);
                if strcmp(name,'SymScore')
                    merged = max(vcl, [], 1, 'omitnan');
                else
                    merged = mean(vcl, 1, 'omitnan');
                end
                out.(name) = [out.(name); merged]; %#ok<AGROW>
            elseif iscell(val) && numel(val) == N
                % cell 字段：继承代表目标（例如 boundaries）
                out.(name) = [out.(name); val(rep)]; %#ok<AGROW>
            else
                % keep as-is (non-numeric or mismatch); do nothing
            end
        end
    end

    Data = out;
end