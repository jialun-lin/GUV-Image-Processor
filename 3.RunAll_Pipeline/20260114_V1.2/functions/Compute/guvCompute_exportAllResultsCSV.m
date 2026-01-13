function T = guvCompute_exportAllResultsCSV(AllResults, outCsvPath, SeriesName, SeriesID, CNames)
%GUVCOMPUTE_EXPORTALLRESULTSCSV 将 Computation/AllResults.mat 展平导出为 CSV
% =========================================================================
% 目标：把 AllResults(结构体数组，按轨迹ID索引) 导出成“长表”CSV，便于跨 XY 汇总。
%
% 每行 = (一个轨迹 ID 在某一帧的一个观测)
% 推荐列：
%   SeriesName, SeriesID, TrackID, Frame,
%   CentroidX, CentroidY, MajorAxisLength,
%   Volume_um3, Surface_um2, Nu, M_tilde, I_Gauss, Rb, R_ve_um,
%   SymmetryScore, IsValid,
%   以及（若存在）meanIntensities_*_C01/C02
%
% 输入：
%   AllResults  : 结构体数组（AllResults(id) 对应轨迹 id；可能存在空元素）
%   outCsvPath  : 输出 CSV 路径
%   SeriesName  : e.g. 'XY001'
%   SeriesID    : 数值型 series 序号
%
% 输出：
%   T : 导出的 table（同时写入 CSV）

if nargin < 2 || isempty(outCsvPath)
    outCsvPath = fullfile(pwd, 'AllResults.csv');
end

if nargin < 5
    CNames = [];
end

if nargin < 3 || isempty(SeriesName)
    SeriesName = "";
end
if nargin < 4 || isempty(SeriesID)
    SeriesID = nan;
end

rows = {};

for id = 1:numel(AllResults)
    R = AllResults(id);
    if ~isstruct(R) || ~isfield(R,'ID') || isempty(R.ID)
        continue;
    end

    % 帧数
    if isfield(R,'Frames') && ~isempty(R.Frames)
        frames = R.Frames(:);
        n = numel(frames);
    else
        continue;
    end

    % 轨迹级字段
    trackID = id;
    if isfield(R,'ID') && ~isempty(R.ID)
        trackID = R.ID;
    end

    % 逐帧字段：统一长度到 n
    cx = nan(n,1); cy = nan(n,1);
    if isfield(R,'Centroids') && ~isempty(R.Centroids) && size(R.Centroids,2) >= 2
        tmp = R.Centroids;
        m = min(n, size(tmp,1));
        cx(1:m) = tmp(1:m,1);
        cy(1:m) = tmp(1:m,2);
    end

    maj = nan(n,1);
    if isfield(R,'MajorAxisLength') && ~isempty(R.MajorAxisLength)
        tmp = R.MajorAxisLength(:);
        m = min(n, numel(tmp));
        maj(1:m) = tmp(1:m);
    end

    V = localPadVec(getField(R,'Volume_um3'), n);
    S = localPadVec(getField(R,'Surface_um2'), n);
    Nu = localPadVec(getField(R,'Nu'), n);
    Mt = localPadVec(getField(R,'M_tilde'), n);
    IG = localPadVec(getField(R,'I_Gauss'), n);
    Rb = localPadVec(getField(R,'Rb'), n);
    Rve = localPadVec(getField(R,'R_ve_um'), n);
    Sym = localPadVec(getField(R,'SymmetryScore'), n);
    IsValid = localPadLogical(getField(R,'IsValid'), n);

    % 可选强度字段
    bg1 = localPadVec(getField(R,'meanIntensities_bg_C01'), n);
    bg2 = localPadVec(getField(R,'meanIntensities_bg_C02'), n);
    in1 = localPadVec(getField(R,'meanIntensities_inner_C01'), n);
    in2 = localPadVec(getField(R,'meanIntensities_inner_C02'), n);
    mm1 = localPadVec(getField(R,'meanIntensities_mem_C01'), n);
    mm2 = localPadVec(getField(R,'meanIntensities_mem_C02'), n);

    T0 = table(...
        repmat(string(SeriesName), n, 1), repmat(SeriesID, n, 1), repmat(trackID, n, 1), frames, ...
        cx, cy, maj, ...
        V, S, Nu, Mt, IG, Rb, Rve, ...
        Sym, IsValid, ...
        bg1, bg2, in1, in2, mm1, mm2, ...
        'VariableNames', { ...
            'SeriesName','SeriesID','TrackID','Frame', ...
            'CentroidX','CentroidY','MajorAxisLength', ...
            'Volume_um3','Surface_um2','Nu','M_tilde','I_Gauss','Rb','R_ve_um', ...
            'SymmetryScore','IsValid', ...
            'meanIntensities_bg_C01','meanIntensities_bg_C02', ...
            'meanIntensities_inner_C01','meanIntensities_inner_C02', ...
            'meanIntensities_mem_C01','meanIntensities_mem_C02' ...
        });

    rows{end+1} = T0; %#ok<AGROW>
end

if isempty(rows)
    T = table();
else
    rows = guvUtil_alignTablesForVertcat(rows);
    T = vertcat(rows{:});
end

% 写 CSV
[outDir,~,~] = fileparts(outCsvPath);
if ~isempty(outDir) && ~exist(outDir,'dir')
    mkdir(outDir);
end
writetable(T, outCsvPath);

% 自定义 CSV 表头：把 *_C01/C02... 改成 <CName>_*（例如 488_meanIntensities_bg）
if ~isempty(CNames)
    hdr = localMakeChannelHeader(T.Properties.VariableNames, CNames);
    localRewriteCsvHeader(outCsvPath, hdr);
end

end

% -------------------- local helpers（不拆成子函数文件） --------------------
function v = getField(S, name)
if isfield(S, name)
    v = S.(name);
else
    v = [];
end
end

function y = localPadVec(x, n)
% 数值向量补齐/截断到 n，缺失填 NaN
if isempty(x)
    y = nan(n,1);
    return;
end
x = x(:);
y = nan(n,1);
m = min(n, numel(x));
y(1:m) = x(1:m);
end

function y = localPadLogical(x, n)
% 逻辑向量补齐/截断到 n，缺失填 false
if isempty(x)
    y = false(n,1);
    return;
end
if ~islogical(x)
    x = logical(x);
end
x = x(:);
y = false(n,1);
m = min(n, numel(x));
y(1:m) = x(1:m);
end
% -------------------- local helpers（channel header） --------------------
function hdr = localMakeChannelHeader(vars, CNames)
%localMakeChannelHeader 把变量名里的 _C01/_C02... 替换为 CNames 前缀。
% 例：meanIntensities_bg_C01 -> 488_meanIntensities_bg
hdr = vars;
if isempty(vars) || isempty(CNames)
    return;
end
if isstring(CNames)
    CNames = cellstr(CNames);
end
if ischar(CNames)
    CNames = cellstr(CNames);
end

for ci = 1:numel(CNames)
    cname = CNames{ci};
    if isempty(cname), continue; end
    cname = regexprep(cname, '\s+', '');
    cname = strrep(cname, ',', '_');

    suf = sprintf('_C%02d', ci);
    for k = 1:numel(vars)
        v = vars{k};

        % case A: suffix style: xxx_C01
        if endsWith(v, suf)
            base = regexprep(v, [suf '$'], '');
            hdr{k} = sprintf('%s_%s', cname, base);
        end
    end
end
end


function localRewriteCsvHeader(fp, header)
%localRewriteCsvHeader 用自定义 header 覆盖 CSV 第一行（不改数据行）
% 说明：此函数只改写 CSV 文件首行文本，不触碰表格数据。
if isempty(header) || ~isfile(fp)
    return;
end

fid = -1;
fidw = -1;
try
    fid = fopen(fp, 'r');
    if fid < 0
        return;
    end

    % 读取并丢弃原始第一行
    fgetl(fid);
    rest = fread(fid, '*char')';
    fclose(fid);
    fid = -1;

    fidw = fopen(fp, 'w');
    if fidw < 0
        return;
    end

    fprintf(fidw, '%s\n', strjoin(header, ','));
    fwrite(fidw, rest, 'char');
    fclose(fidw);
    fidw = -1;

catch
    % 安全关闭（避免 fclose(无效fid) 抛错）
    if fid > 0
        try, fclose(fid); catch, end
    end
    if fidw > 0
        try, fclose(fidw); catch, end
    end
end
end

