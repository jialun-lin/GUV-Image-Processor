function TTracks = guvSeries_trackFromMats(Paths, Cfg, Thr, frameGetter)
%GUVSERIES_TRACKFROMMATS 读取 FramesMAT 并运行 guvTrack_trackCentroids。
files = guvUtil_sortFrameFiles(dir(fullfile(Paths.OutFrames, 'Time_*_Data.mat')));

trackOpts = Cfg.Track.Opts;
trackOpts.StoreImg = false;
trackOpts.SaveDiag = true;
trackOpts.DiagOutDir = fullfile(Paths.OutSeries, 'TrackDiag');
trackOpts.DiagTag = sprintf('%s_%s', Paths.SeriesName, Paths.CName);
if ~isempty(frameGetter)
    trackOpts.FrameGetter = frameGetter;
end

TTracks = guvTrack_trackCentroids(files, Thr.trackGate_px, Cfg.Track.MinLen, Cfg.Track.MaxGap, trackOpts);

% （可选）把每帧每个GUV的轮廓线(boundary)挂到轨迹上，随 TTracks.mat 一起保存
if isfield(Cfg,'Track') && isfield(Cfg.Track,'SaveBoundary') && Cfg.Track.SaveBoundary
    try
        maxDist_um = Cfg.Track.BoundaryMatch_um;
        if isempty(maxDist_um) || maxDist_um <= 0
            maxDist_um = 3;
        end
        maxDist_px = maxDist_um / Thr.px;
        TTracks = guvTrack_attachBoundariesFromFrameMats(files, TTracks, maxDist_px);
    catch ME
        warning('Attach boundaries to TTracks failed: %s', ME.message);
    end
end

% 保存
if Cfg.Output.SaveTracksMAT
    outMat = fullfile(Paths.OutSeries, 'TTracks.mat');
    s = whos('TTracks');
    if s.bytes > 2^31-1
        save(outMat, 'TTracks', 'Cfg', '-v7.3');
    else
        save(outMat, 'TTracks', 'Cfg', '-v7');
    end
end
end
