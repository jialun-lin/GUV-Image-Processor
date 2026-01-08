function AllXYResults = guvCompute_collectAllXYResults(OutRoot, SeriesPrefix)
%GUVCOMPUTE_COLLECTALLXYRESULTS 汇总所有 XY 的 AllResults.csv 为一个总表
% =========================================================================
% 目标：根据每个 XY 子目录下的
%   XY###/Computation/AllResults.csv
% 汇总生成 OutputPath 根目录的 AllXYResults.csv（用于替代 GUV_MASTER_DB.csv 的“总表”作用）。
%
% 输入：
%   OutRoot      : Pipeline 输出根目录（OutputPath）
%   SeriesPrefix : 子目录前缀（默认 'XY'）
%
% 额外：
%   - 输出会新增 GlobalID 列：对每个 (SeriesName, TrackID) 生成全局唯一ID，
%     便于跨 XY 统计/过滤。
%
% 输出：
%   AllXYResults : 汇总后的 table（若没有找到任何 AllResults.csv，则为空表）

    if nargin < 1 || isempty(OutRoot)
        error('OutRoot 为空。');
    end
    if nargin < 2 || isempty(SeriesPrefix)
        SeriesPrefix = 'XY';
    end

    patt = fullfile(OutRoot, sprintf('%s*', SeriesPrefix), 'Computation', 'AllResults.csv');
    files = dir(patt);

    if isempty(files)
        AllXYResults = table();
        return;
    end

    % ------- 按 XY 序号排序，保证 GlobalID 的叠加顺序稳定 -------
    seriesNum = nan(numel(files),1);
    for i = 1:numel(files)
        % e.g. .../XY001/Computation/AllResults.csv
        p = files(i).folder;
        [~, xyName] = fileparts(fileparts(p)); % 上两级得到 XY###
        tok = regexp(xyName, sprintf('^%s(\\d+)$', SeriesPrefix), 'tokens', 'once');
        if ~isempty(tok)
            seriesNum(i) = str2double(tok{1});
        end
    end
    [~, ord] = sort(seriesNum);
    files = files(ord);

    % ------- 读取并分配 GlobalID（计数叠加） -------
    % 规则：GlobalID = TrackID + offset；offset 为已处理 series 的 TrackID 最大值累加
    Ts = cell(numel(files),1);
    offset = 0;

    for i = 1:numel(files)
        fp = fullfile(files(i).folder, files(i).name);
        try
            T = readtable(fp, 'PreserveVariableNames', true);
        catch
            T = readtable(fp);
        end

        if ~ismember('TrackID', T.Properties.VariableNames)
            error('AllResults.csv 缺少 TrackID 列：%s', fp);
        end

        % 统一 SeriesName：若缺失则从路径推断
        if ~ismember('SeriesName', T.Properties.VariableNames)
            [~, xyName] = fileparts(fileparts(files(i).folder));
            T.SeriesName = repmat(string(xyName), height(T), 1);
        end

        % GlobalID（计数叠加）
        tid = T.TrackID;
        if ~isnumeric(tid)
            tid = double(tid);
        end
        T.GlobalID = tid + offset;

        tidValid = tid(~isnan(tid));
        if ~isempty(tidValid)
            offset = offset + max(tidValid);
        end

        Ts{i} = T;
    end

    Ts = guvUtil_alignTablesForVertcat(Ts);
    AllXYResults = vertcat(Ts{:});

    % 写到 OutRoot
    outCsv = fullfile(OutRoot, 'AllXYResults.csv');
    writetable(AllXYResults, outCsv);

end
