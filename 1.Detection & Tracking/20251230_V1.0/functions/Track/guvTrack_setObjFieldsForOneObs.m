function trk = guvTrack_setObjFieldsForOneObs(trk, G, oi, objFields)
    for k = 1:numel(objFields)
        fn = objFields{k};
        if ~isfield(G, fn) || isempty(G.(fn))
            trk.(fn) = nan(1,1);
            continue;
        end
        val = G.(fn);
        if (isnumeric(val) || islogical(val)) && size(val,1) >= oi
            trk.(fn) = val(oi,:);
        else
            trk.(fn) = nan(1,1);
        end
    end
end

