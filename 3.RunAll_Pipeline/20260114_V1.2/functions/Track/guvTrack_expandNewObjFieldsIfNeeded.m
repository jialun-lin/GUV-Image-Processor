function [objFields, baseTrack, TTracks] = guvTrack_expandNewObjFieldsIfNeeded(G, nObj, objFields, baseTrack, TTracks, imgFieldName, sizeFieldName)
    newFields = guvTrack_inferObjFields(G, nObj, imgFieldName, sizeFieldName);

    for i = 1:numel(newFields)
        fn = newFields{i};
        if any(strcmp(objFields, fn))
            continue;
        end

        % 新字段加入 objFields
        objFields{end+1} = fn; %#ok<AGROW>

        % baseTrack 增加字段
        baseTrack.(fn) = [];

        % 所有已有轨迹也补上该字段
        for t = 1:numel(TTracks)
            TTracks(t).(fn) = [];
        end
    end
end

% =========================================================================
% helpers: shape cost (optional)
% =========================================================================
