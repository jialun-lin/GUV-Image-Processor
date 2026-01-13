function objFields = guvTrack_inferObjFields(G, nObj, imgFieldName, sizeFieldName)
    objFields = {};
    allFields = fieldnames(G);
    for i = 1:numel(allFields)
        fn = allFields{i};
        if strcmp(fn,imgFieldName) || strcmp(fn,sizeFieldName)
            continue;
        end
        v = G.(fn);
        if (isnumeric(v) || islogical(v)) && ~isempty(v) && size(v,1) == nObj
            objFields{end+1} = fn; %#ok<AGROW>
        end
    end
end

