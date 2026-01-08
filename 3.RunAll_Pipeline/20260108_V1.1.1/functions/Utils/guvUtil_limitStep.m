function d = guvUtil_limitStep(d, maxStep)
%GUVUTIL_LIMITSTEP 限制二维位移向量 d 的模长不超过 maxStep。
if isempty(d) || any(~isfinite(d)) || numel(d)~=2
    return;
end
if nargin < 2 || isempty(maxStep) || ~isfinite(maxStep)
    return;
end
n = hypot(d(1), d(2));
if n > maxStep && n > 0
    d = d / n * maxStep;
end
end
