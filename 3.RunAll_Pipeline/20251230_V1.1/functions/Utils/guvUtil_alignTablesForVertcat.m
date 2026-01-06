function tables = guvUtil_alignTablesForVertcat(tables)
%GUVALIGNTABLESFORVERTCAT 让多个 table 具有相同变量集合，便于 vertcat
%  用途：
%   - 不同通道/不同配置可能会导出不同列（例如双通道补全字段只在 Ref 通道存在）。
%   - 直接 vertcat 会报错：所有垂直串联的表必须具有相同的变量数。
%
%  规则：
%   1) 取所有表变量名的并集（union）。
%   2) 对缺失变量的表：补齐同名列，按“原型表”的数据类型填充默认缺失值。
%   3) 最终统一列顺序为 union 的顺序（稳定、可复现）。

if isempty(tables); return; end

% 过滤非 table
keep = true(size(tables));
for i = 1:numel(tables)
    keep(i) = istable(tables{i});
end
tables = tables(keep);
if isempty(tables); return; end

% 收集所有变量名（并集）
allVars = strings(0,1);
for i = 1:numel(tables)
    allVars = [allVars; string(tables{i}.Properties.VariableNames(:))]; %#ok<AGROW>
end
allVars = unique(allVars, 'stable');

% 为每个变量寻找一个“原型列”，用于确定类型
protoMap = containers.Map('KeyType','char','ValueType','any');
for v = allVars.'
    vch = char(v);
    for i = 1:numel(tables)
        Ti = tables{i};
        if any(strcmp(Ti.Properties.VariableNames, vch))
            protoMap(vch) = Ti.(vch);
            break;
        end
    end
end

% 补齐缺失变量
for i = 1:numel(tables)
    T = tables{i};
    n = height(T);
    curVars = string(T.Properties.VariableNames(:));
    missVars = setdiff(allVars, curVars, 'stable');
    for mv = missVars.'
        name = char(mv);
        proto = protoMap(name);

        if isstring(proto)
            T.(name) = strings(n,1);
        elseif iscell(proto) && ~isempty(proto) && ischar(proto{1})
            T.(name) = strings(n,1);
        elseif iscategorical(proto)
            T.(name) = categorical(zeros(n,1)); % 未定义类别时给空类别
        elseif isdatetime(proto)
            T.(name) = NaT(n,1);
        elseif islogical(proto)
            T.(name) = false(n,1);
        else
            % 数值/其它：用 NaN
            T.(name) = nan(n,1);
        end
    end

    % 统一列顺序
    T = T(:, cellstr(allVars));
    tables{i} = T;
end
end
