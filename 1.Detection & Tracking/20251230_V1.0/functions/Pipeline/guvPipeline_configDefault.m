function Cfg = guvPipeline_configDefault()
%GUVCONFIG_DEFAULT 参数中心（重构后精简版）
% =========================================================================
% 重要原则（团队协作建议）：
%   1) 只在本文件改“开关/阈值/路径”。算法实现细节在 Detect/Fuse/Track 内部函数。
%   2) 本配置只覆盖“读图→检测→同帧融合→追踪→导出(TTracks/表格/调试视频)”链路。
%      不包含追踪后的计算/过滤/可视化。
%
% 你最终确认的三条核心规则：
%   (R1) 每个通道都能生成对象 mask；若同一对象在两通道都存在，取 imfill 后面积更大者为主 ref mask。
%   (R2) 所有通道的强度（inner/mem/bg）统一在“主 ref mask（subMask + memBandMask）”上测量。
%   (R3) Cfg.Read.CType 仅决定“识别时如何构造 mask”（inner 或 mem），不改变强度的物理含义。
%       - meanIntensity_inner：实心区域平均强度（subMask）
%       - meanIntensity_mem  ：实心区域边界固定厚度环带平均强度（memBandMask）
%
% 使用：
%   Cfg = guvPipeline_configDefault();
%   MasterTable = GUV_Pipeline(Cfg);

Cfg = struct();

%% ============================= 1) 路径与输出 =============================
Cfg.ND2Path = 'E:\GUV\GUV_Image_Analysis\Sample\2025.1122\20251122.nd2';
Cfg.OutRoot = 'E:\GUV\GUV_Image_Analysis\Out_ModularB_Clean';
Cfg.SeriesPrefix = 'XY';  % 输出子文件夹前缀：XY001/XY002...

%% ============================= 2) 像素尺寸（um/px） ======================
% 若 ND2 metadata 可读取到像素尺寸，Pipeline 会自动覆盖此值。
Cfg.PixelSize_um = 0.13;

%% 帧间隔（秒/帧）：用于把帧号换算成时间轴（表格导出/视频标注）
% 若 ND2 metadata 可读取到帧间隔，Pipeline 会自动覆盖此值。
Cfg.FrameInterval_s = 1.0;

%% ============================= 3) 读取设置（Series / Z / 通道） ===========
Cfg.Read = struct();
Cfg.Read.SelectXYs = [];     % 例如 [2 5 10]；空=[]表示全跑
Cfg.Read.Z = 1;              % 本项目默认 Z=1
Cfg.Read.CList  = [1 2];     % 需要读取的通道序号（bfGetPlaneAtZCT 的 C）
Cfg.Read.CNames = {'488','640'};            % 用于输出命名/表格列名提示
Cfg.Read.CType  = {'inner','mem'};          % 仅影响识别 mask 构造：'inner' 或 'mem'
Cfg.Read.RefC   = 1;         % “显示/组织输出”的主通道：用于输出目录命名、legacy字段(meanIntensities)映射、视频背景
Cfg.Read.OtherC = [];        % 可选：指定另一个通道（用于双通道Debug面板/视频）；空=[]则自动取非RefC的第一个通道

%% ============================= 4) 同帧融合（Fuse） ========================
% 只负责“同一帧内”把两通道对象配对并选主 ref mask（更大面积者）。
Cfg.Fuse = struct();
Cfg.Fuse.Pair = struct();
Cfg.Fuse.Pair.MaxDist_um = 6;    % 质心配对距离门限（µm），典型 3~10
Cfg.Fuse.Pair.UseIoU = true;     % 是否用 IoU 做二次确认（膜/内水差异大时可开）
Cfg.Fuse.Pair.MinIoU = 0.05;     % IoU 下限（可很低）

%% ============================= 5) 检测（Detect） =========================
Cfg.Detect = struct();

% 目标尺寸筛选（主轴长度范围，µm）
Cfg.Detect.MinMajor_um = 2;
Cfg.Detect.MaxMajor_um = 50;

% (旧逻辑保留) inner-mem 合并后的“近邻去重/合并”：
% - 你要求：在新逻辑中等价于“只作用于 CType='mem' 的通道”。
Cfg.Detect.SuppressCloseOnMem = true;
Cfg.Detect.SuppressDist_um = 2;  % 近邻阈值（µm）

% Detect.Opts：检测内部参数（尽量少且清晰）
opts = struct();

% --- 预处理/阈值 ---
opts.bin.sigma = 1.2;        % 高斯平滑 sigma（px）
opts.bin.adapt_sensitivity = 0.45; % adaptive threshold 灵敏度（0~1，越大越容易判为前景）
opts.bin.minHoleArea = 10;   % 填洞最小面积（px^2）

% --- 形态学清理 ---
opts.inner.areaOpen = 50;    % 去除小连通域（px^2）

% --- 可选：分割（对粘连很重时启用；与后处理分水岭不同）---
opts.split.doSplit = false;
opts.split.openR  = 2;       % 开运算半径（px）
opts.split.splitH = 2.0;     % h-minima（越小越容易分割）

% --- 薄环(memBand)：固定厚度，用于 meanIntensity_mem ---
opts.band.width_px = 3;      % 环带厚度（px），典型 2~5
opts.mem = struct();
opts.mem.thickR  = opts.band.width_px; % 与 guvDetect_computeMemBandFromSubMasks 一致（imdilate/imerode 半径）
opts.mem.smoothR = 2;                 % 膜mask平滑半径（用于生成更稳定的band边界）

% --- Detect Debug figure（批量建议 false；单XY调试用）---
opts.debug.makeFigure = false;

Cfg.Detect.Opts = opts;

%% ============================= 6) 后处理分割（面积覆盖率自适应分水岭） ====
% 对照旧包：guvDetect_postSplitByCoverageWatershed（保留，且阈值可控）
Cfg.Post = struct();
Cfg.Post.Watershed = struct();
Cfg.Post.Watershed.Enable = false;

% Tau：面积覆盖率阈值（越小越容易触发“更激进”的分割）
Cfg.Post.Watershed.Tau = 0.70;

% hLow/hHigh：h-minima 的两档值（低：更容易分割；高：更保守）
Cfg.Post.Watershed.hLow  = 1.0;
Cfg.Post.Watershed.hHigh = 3.0;

% SigmaD：距离变换平滑尺度（px）
Cfg.Post.Watershed.SigmaD = 1.0;

% MinAreaPx：子区域最小面积（px^2），过小的分割碎片丢弃
Cfg.Post.Watershed.MinAreaPx = 40;

% MarginPx：ROI 扩边（避免边界截断影响分割）
Cfg.Post.Watershed.MarginPx = 4;

% MaxChild：最多保留的子区域数（防止爆炸式过分割）
Cfg.Post.Watershed.MaxChild = 4;

%% ============================= 7) 追踪（Track） ==========================
Cfg.Track = struct();
Cfg.Track.DistGate_um = 8;      % 帧间关联距离门限（µm）
Cfg.Track.MaxGap = 2;           % 最大断帧数
Cfg.Track.MinLen = 5;           % 最短轨迹长度（过滤噪声）
Cfg.Track.Opts = struct();
Cfg.Track.Opts.DistGate_um = Cfg.Track.DistGate_um;
Cfg.Track.Opts.MaxGap = Cfg.Track.MaxGap;
Cfg.Track.Opts.MinLen = Cfg.Track.MinLen;
Cfg.Track.Opts.EstimateGlobalDrift = true;  % 全局漂移估计（整体漂移明显时强烈建议 true）
Cfg.Track.Opts.IoUUseFilledMask = false;  % 若追踪内部使用 IoU，可选择用 filled mask 计算

%% ============================= 8) 输出控制（IO） ==========================
Cfg.Output = struct();
Cfg.Output.SavePerFrameMAT   = true;
Cfg.Output.SaveImgInFrameMAT = false;  % 强烈建议 false（避免磁盘爆炸）；视频背景用 FrameStore
Cfg.Output.SaveFrameStore    = true;   % 建议 true：保存一个 HDF5 用于视频背景与快速回读
Cfg.Output.FrameStoreName    = 'FrameStore.h5';
Cfg.Output.FrameStoreDeflate = 1;      % HDF5 压缩等级 0~9（1即可）
Cfg.Output.SaveTracksMAT     = true;
Cfg.Output.SaveCSV           = true;

%% ============================= 9) 调试（Debug） ==========================
Cfg.Debug = struct();
Cfg.Debug.Enable       = true;  % 是否允许输出 debug（总开关）
Cfg.Debug.SingleXYOnly = true;  % 批量跑时只对“单XY”输出 PNG/视频（避免爆炸）
Cfg.Debug.MaxFrames    = [];    % 限制最大帧数（空=[]表示全帧）
Cfg.Debug.SaveFramePNG = true;  % 输出逐帧PNG（单XY调试）
Cfg.Debug.SaveFuseLog  = true;  % 输出融合统计（配对数/主ref来自哪个通道等）
Cfg.Debug.SaveVideo    = true;  % 输出 debug 视频
Cfg.Debug.VideoFPS     = 10;    % 视频帧率
Cfg.Debug.VideoShowC   = Cfg.Read.RefC; % 视频背景通道（默认=RefC）
Cfg.Debug.TailLen      = 25;    % 轨迹尾巴长度（帧）
Cfg.Debug.ShowMemBand = true; % Debug 面板/视频叠加主ref的 memBand 轮廓（用于检查环带厚度）
Cfg.Debug.ShowMemMask = false; % Debug 面板叠加该通道自身 memMask 轮廓（只对 CType=mem 有意义；默认关闭以免太乱）
Cfg.Debug.SaveVideoBoth = true; % 若存在 OtherC，则额外保存一份以 OtherC 为底图的视频
Cfg.Debug.ShowOutline  = true;
Cfg.Debug.OutlineColor = 'y';   % 叠加轮廓颜色（字符即可，简单）
Cfg.Debug.OutlineLineWidth = 1.2;
Cfg.Debug.Verbose      = true;  % 控制命令行输出

%% ============================= 10) 并行（Parallel） =======================
Cfg.Parallel = struct();
Cfg.Parallel.Enable = false; % 需要 parfor 时打开（注意：debug 输出会自动收敛）

end