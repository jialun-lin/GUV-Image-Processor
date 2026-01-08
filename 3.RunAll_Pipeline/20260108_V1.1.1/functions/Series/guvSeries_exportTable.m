function LocalTable = guvSeries_exportTable(Paths, Cfg, TTracks)
%GUVSERIES_EXPORTTABLE 导出 per-series 表格并写 CSV。
LocalTable = guvTrack_tracksToTable(TTracks, Paths.SeriesName, Cfg.FrameInterval_s);
LocalTable.Channel = repmat(string(Paths.CName), height(LocalTable), 1);

csvPath = fullfile(Paths.OutSeries, sprintf('%s_%s_Table.csv', Paths.SeriesName, Paths.CName));
if Cfg.Output.SaveCSV
    writetable(LocalTable, csvPath);
end
end
