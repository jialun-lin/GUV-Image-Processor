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
