function trk = guvTrack_appendObjFieldsOneObs(trk, G, oi, objFields)
    for k = 1:numel(objFields)
        fn = objFields{k};

        if ~isfield(G, fn) || isempty(G.(fn))
            row = nan(1, size(trk.(fn),2));
        else
            val = G.(fn);
            if (isnumeric(val) || islogical(val)) && size(val,1) >= oi
                row = val(oi,:);
            else
                row = nan(1, size(trk.(fn),2));
            end
        end

        if isempty(trk.(fn))
            trk.(fn) = row;
        else
            c0 = size(trk.(fn),2);
            c1 = size(row,2);
            if c1 < c0
                row = [row, nan(1, c0-c1)];
            elseif c1 > c0
                trk.(fn) = [trk.(fn), nan(size(trk.(fn),1), c1-c0)];
            end
            trk.(fn) = [trk.(fn); row];
        end
    end
end

% =========================================================================
% FFT phase correlation: estimate drift (dx,dy)
% =========================================================================
