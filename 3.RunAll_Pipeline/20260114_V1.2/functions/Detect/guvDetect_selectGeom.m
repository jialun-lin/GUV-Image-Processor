function geomOut = guvDetect_selectGeom(geomIn, validMask)
%LOCALSELECTGEOM 选择几何字段（用于 mem/inner 模式下对 geom 输出做一致性筛选）
% 目的：
%   - 当 opts.geom.enable=false 时，geomIn 可能为空或缺字段；此时返回“空结构”，避免报错。
%   - 当 geomIn 的字段长度与 validMask 对应的检测目标数一致时，按 validMask 筛选。
%
% 输入：
%   geomIn   : 结构体（可能为空），字段常见为 A_axisym, V_axisym, Rve, ...
%   validMask: 逻辑向量（长度=原始候选目标数量）
% 输出：
%   geomOut  : 结构体（字段保持一致；若无可用字段则返回空字段）

    % 预置一个“空输出”，确保下游字段访问安全
    geomOut = struct();

    if nargin < 2 || isempty(validMask)
        % 没有筛选需求，直接返回（尽量保持字段）
        if isstruct(geomIn)
            geomOut = geomIn;
        end
        return;
    end

    if isempty(geomIn) || ~isstruct(geomIn)
        % 未启用 geom 或 geom 输出不存在
        return;
    end

    fns = fieldnames(geomIn);
    if isempty(fns)
        return;
    end

    n0 = numel(validMask);

    % 对每个字段：如果它是数值数组且第一维等于 n0，则按 validMask 选择行
    for k = 1:numel(fns)
        fn = fns{k};
        v = geomIn.(fn);

        try
            if isnumeric(v) && ~isempty(v) && size(v,1) == n0
                geomOut.(fn) = v(validMask, :);
            else
                % 不满足“逐目标一行”的字段，原样拷贝（例如标量、参数、空等）
                geomOut.(fn) = v;
            end
        catch
            % 容错：任何异常都不让程序挂掉
            geomOut.(fn) = v;
        end
    end
end
