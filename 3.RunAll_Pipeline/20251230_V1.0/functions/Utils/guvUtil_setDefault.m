function S = guvUtil_setDefault(S, name, val)
%GUVUTIL_SETDEFAULT 若结构体 S 不含字段 name 或该字段为空，则赋默认值 val。
if ~isfield(S, name) || isempty(S.(name))
    S.(name) = val;
end
end
