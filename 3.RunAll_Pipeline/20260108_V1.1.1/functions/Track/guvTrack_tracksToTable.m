function T = guvTrack_tracksToTable(TTracks, SeriesName, dt)
%GUVTRACKSTOTABLE Convert track struct to long table (one row per frame)

if nargin < 3 || isempty(dt), dt = 1; end

T = table();
if isempty(TTracks)
    return;
end

% choose a core set of fields if present
baseFields = {'centroids','majorAxisLength','Areas','Perimeter','meanIntensities','SymScore', ...
              'A_axisym','V_axisym','Rve','nu','IM','IG','IG_relerr','neck_r'};

for k = 1:numel(TTracks)
    frames = TTracks(k).frames(:);
    n = numel(frames);

    Tk = table(repmat({SeriesName}, n, 1), repmat(TTracks(k).ID, n, 1), ...
        frames, (frames-1)*dt, 'VariableNames', {'Series','TrackID','Frame','Time_s'});

    % centroids -> X,Y
    if isfield(TTracks(k),'centroids') && ~isempty(TTracks(k).centroids)
        Tk.X = TTracks(k).centroids(:,1);
        Tk.Y = TTracks(k).centroids(:,2);
    else
        Tk.X = nan(n,1); Tk.Y = nan(n,1);
    end

    % append numeric fields if exist
    for i = 1:numel(baseFields)
        fn = baseFields{i};
        if strcmp(fn,'centroids'), continue; end
        if isfield(TTracks(k), fn) && ~isempty(TTracks(k).(fn))
            val = TTracks(k).(fn);
            if isvector(val) && numel(val)==n
                Tk.(fn) = val(:);
            elseif size(val,1)==n && size(val,2)==1
                Tk.(fn) = val;
            else
                % skip incompatible
            end
        end

    % 自动追加额外的数值型逐帧字段（例如：meanIntensities_C01 / meanIntensities_C02）
    % 说明：
    %   - 避免每次新增荧光字段都要手动改 baseFields；
    %   - 同时排除 mask/bbox/boundary 等大对象字段，避免表过大/类型不兼容。
    fnsAll = fieldnames(TTracks(k));
    exclude = {'subMasks','boundaries','bboxes','I','imageSize','FrameGetter','kalmanFilter'};
    for ii = 1:numel(fnsAll)
        fn = fnsAll{ii};
        if any(strcmp(fn, exclude)), continue; end
        if isfield(Tk, fn), continue; end % 已经写入的字段跳过
        val = TTracks(k).(fn);
        if isnumeric(val) && ~isempty(val)
            if isvector(val) && numel(val)==n
                Tk.(fn) = val(:);
            elseif size(val,1)==n && size(val,2)==1
                Tk.(fn) = val;
            end
        end
    end

    end

    T = [T; Tk]; %#ok<AGROW>
end

end
