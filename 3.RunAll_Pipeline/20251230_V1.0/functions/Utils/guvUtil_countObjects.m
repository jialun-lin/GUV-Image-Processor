function n = guvUtil_countObjects(S)
%GUVUTIL_COUNTOBJECTS 尽量稳健地判断单帧结构体中对象数量。
% 优先级：centroids > bboxes > Areas/areas。
n = 0;
if isfield(S,'centroids') && ~isempty(S.centroids)
    n = size(S.centroids,1); return;
end
if isfield(S,'bboxes') && ~isempty(S.bboxes)
    n = size(S.bboxes,1); return;
end
if isfield(S,'Areas') && ~isempty(S.Areas)
    n = numel(S.Areas); return;
end
if isfield(S,'areas') && ~isempty(S.areas)
    n = numel(S.areas); return;
end
end
