function v = guvUtil_getFieldOr(S, fname, fallback)
%GUVUTIL_GETFIELDOR 安全获取结构体字段，缺失或空则返回 fallback。
if nargin < 3, fallback = []; end
if isstruct(S) && isfield(S, fname)
    v = S.(fname);
    if isempty(v)
        v = fallback;
    end
else
    v = fallback;
end
end
