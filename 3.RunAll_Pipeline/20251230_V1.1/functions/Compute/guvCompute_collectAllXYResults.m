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

    Ts = cell(numel(files),1);
    for i = 1:numel(files)
        fp = fullfile(files(i).folder, files(i).name);
        try
            Ts{i} = readtable(fp, 'PreserveVariableNames', true);
        catch
            Ts{i} = readtable(fp);
        end
    end

    Ts = guvUtil_alignTablesForVertcat(Ts);
    AllXYResults = vertcat(Ts{:});

    % 写到 OutRoot
    outCsv = fullfile(OutRoot, 'AllXYResults.csv');
    writetable(AllXYResults, outCsv);

end
