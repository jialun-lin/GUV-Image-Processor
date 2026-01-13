
---

# README｜GUV Detection & Tracking (Modular, Main-Ref Masks)

## 1. 项目简介

本脚本包用于显微镜时间序列（ND2/LIF/TIFF 等）中 GUV（巨型脂质体）的：

* **逐帧检测（Detection）**
* **双通道同帧融合（Fuse）：选择“主 Ref mask”（更大填充面积）**
* **在主 Ref masks 上统一测量所有通道强度（Match/Measure）：inner / mem / bg**
* **帧间追踪（Track）：考虑全局漂移的近邻关联**
* **导出：每帧 MAT、轨迹结构 `TTracks`、表格 CSV、调试图/视频**

> 该版本的重点是“结构重构而非重写算法”：把旧包中易出错、难 debug 的大函数拆成多个小函数，并统一命名、统一 I/O、便于断点检查。

---

## 2. 核心语义规则（团队必须统一）

### 2.1 主体规则（代码已固化）

* **(R1) 几何对象 = 实心 innerMask（填充区域）**
  无论通道是 inner 荧光还是 mem 荧光，最终用于几何/追踪/测量的对象区域都是“实心区域（subMask）”。

* **(R2) 双通道互为 ref：同一对象两通道都检测到 → 取 `imfill` 后面积更大者作为主 Ref mask**
  主 Ref 是**逐对象动态选择**，不是固定某一个通道。

* **(R3) 所有通道强度统一在主 Ref masks 上测量**
  对每个通道 `Cxx` 输出：

  * `meanIntensities_inner_Cxx`：主 Ref 的实心区域（subMask）平均强度
  * `meanIntensities_mem_Cxx`：主 Ref 的固定厚度环带（memBandMask）平均强度
  * `meanIntensities_bg_Cxx`：该通道背景平均强度（每帧一个值复制到对象行）

> `Cfg.Read.CType` **只决定检测时“如何构造 mask”**（inner 或 mem），并不改变强度物理含义：
>
> * inner 强度永远指“实心区域强度”
> * mem 强度永远指“实心区域边界环带强度”

---

## 3. 环境依赖

### 3.1 MATLAB

建议 R2020b+（更老版本通常也可），需要：

* Image Processing Toolbox（`regionprops / bwconncomp / watershed / imfill / bwdist` 等）

### 3.2 Bio-Formats（读取 ND2/LIF）

若输入为 ND2/LIF，需安装 `bfmatlab` 并加入 MATLAB 路径，依赖函数：

* `bfGetReader`
* `bfGetPlaneAtZCT`

---

## 4. 运行方式（唯一入口）

### 4.1 推荐运行（JSON 驱动）

1) 复制模板 `guvPipeline_config_template.json` 到你的输出目录，并重命名为 `guvPipeline_config.json`

2) 修改 JSON 后运行：

```matlab
InputPath  = '...\\xxx.nd2';
OutputPath = '...\\Out_ModularB';
MasterTable = GUV_Pipeline(InputPath, OutputPath); % 自动在 OutputPath 下读取 guvPipeline_config.json
```

也可以显式传入 JSON：

```matlab
MasterTable = GUV_Pipeline(InputPath, OutputPath, '...\\guvPipeline_config.json');
```

### 4.2 兼容旧版（不推荐）

```matlab
Cfg = guvPipeline_configDefault();
Cfg.ND2Path = '...\\xxx.nd2';
Cfg.OutRoot = '...\\Out_ModularB';
MasterTable = GUV_Pipeline(Cfg);
```

2. 选择 XY（Series）

```matlab
Cfg.Read.SelectXYs = [3];   % 只跑 XY003；[] 表示全跑
```

3. 通道设置

```matlab
Cfg.Read.CList  = [1 2];
Cfg.Read.CNames = {'488','640'};
Cfg.Read.CType  = {'inner','mem'};   % 仅影响检测 mask 构造
Cfg.Read.RefC   = 1;                 % 仅用于显示/视频底图/目录命名
% Cfg.Read.OtherC = 2;               % 可不写，自动取非 RefC 的第一个通道
```

4. 检测核心阈值

* `Cfg.Detect.MinMajor_um / MaxMajor_um`
* `Cfg.Detect.Opts.bin.adapt_sensitivity`
* `Cfg.Detect.Opts.inner.areaOpen`

5. mem 环带厚度（用于 `meanIntensities_mem_*`）

* `Cfg.Detect.Opts.band.width_px`（典型 2–5 px）

6. 后处理分水岭（面积覆盖率触发，可控阈值）

* `Cfg.Post.Watershed.Enable`
* `Cfg.Post.Watershed.Tau`（覆盖率阈值）
* `hLow / hHigh / SigmaD / MinAreaPx / MaxChild ...`

7. 追踪门限

* `Cfg.Track.DistGate_um`
* `Cfg.Track.MaxGap`
* `Cfg.Track.MinLen`
* `Cfg.Track.Opts.EstimateGlobalDrift`

### 4.3 （可选）追踪后形态学计算

本包已把你提供的 `GUV-Image-Processor-main` 的 Calculation 脚本封装为单文件函数并接入 Pipeline：

* `functions/Compute/guvCompute_Calculation.m`
* 计算结果会在 `XY###/Computation/AllResults.mat` 与 `AllResults.csv` 中输出。

> 结果的人工检查与绘图（VisualizeSingleID）已从主流程摘出，见 `VisualizeSingleID_Pipeline.zip`。

开启方式：

```matlab
Cfg.Compute.Enable = true;            % 开启计算（默认关闭）
Cfg.Compute.Channel = Cfg.Read.RefC;  % 选择用于分割/轮廓重建的通道
Cfg.Compute.Visualize.Enable = true;  % 是否导出 png
Cfg.Compute.Visualize.IDs = 1:5;      % 可选：只画前 5 个轨迹；[] 表示全部（可能非常大）
```

输出位置：

* 每个 `XY###` 目录下新增 `Computation/`：
  - `AllResults.mat`：原始结构体结果（逐轨迹/逐帧）
  - `AllResults.csv`：将 `AllResults.mat` 展平后的长表（每行=某轨迹在某帧的观测）
  - `Figures/`：可选 png 图（若开启可视化）
* 输出根目录 `OutputPath/` 下新增：
  - `AllXYResults.csv`：自动汇总所有 `XY###/Computation/AllResults.csv` 得到的总表（用于替代 `GUV_MASTER_DB.csv` 的“总表”作用）

---

## 5. 代码结构与命名规范

### 5.1 顶层

* `GUV_Pipeline.m`：唯一入口
* `functions/`：所有函数（全部归类，无散落）

### 5.2 functions/ 子目录

* `functions/Pipeline/`：配置、通道解析、单 Series 串联
* `functions/Series/`：逐帧读图+保存、输出目录、FrameStore、导表、视频调用
* `functions/Detect/`：阈值、形态学、flood-fill 背景、连通域特征、memBand、分水岭后处理等
* `functions/Fuse/`：双通道同帧配对 + 主 Ref 选择（更大 filled area）
* `functions/Match/`：在主 Ref masks 上测各通道 inner/mem/bg
* `functions/Track/`：帧间关联（含漂移估计）、轨迹转表
* `functions/Debug/`：逐帧 PNG（2×2 面板，含 memBand/memMask 可选）、追踪视频
* `functions/IO/`：FrameStore(HDF5)、像素尺寸读取等
* `functions/Utils/`：通用工具

### 5.3 命名约定

统一使用：

* `guvDetect_xxx.m`
* `guvFuse_xxx.m`
* `guvMatch_xxx.m`
* `guvTrack_xxx.m`
* `guvDebug_xxx.m`
* `guvIO_xxx.m`
* `guvUtil_xxx.m`

---

## 6. Pipeline 处理流程（从读图到 TTracks）

### 6.1 Series：逐帧检测 + 融合 + 强度测量 + 保存

主函数：

* `functions/Series/guvSeries_detectSaveLoop_fuseMainRef.m`

每帧 `t` 的核心顺序：

1. 读取所有通道图像 `Icell`
2. 每通道检测：`guvDetect_runFrame(I, CType, ...)` → `detC{cc}`
3. 可选后处理分割：`guvDetect_postSplitByCoverageWatershed(...)`
4. 双通道融合：`guvFuse_twoChannel_mainRef(det1, det2, ...)`

   * 输出融合后的 `GUVData`（几何取逐对象主 Ref）
   * 输出 `FuseLog`（n1/n2/matched/only1/only2）
5. 用主 Ref masks 测所有通道强度：
   `guvMatch_measureChannelOnRefMasks(GUVData, I_c, c, CType, ...)`
6. 保存：`XY###/FramesMAT/Time_XXXX_Data.mat`（变量名固定 `GUVData`）

### 6.2 Detect：单帧检测（inner/mem 两种 CType）

主函数：

* `functions/Detect/guvDetect_runFrame.m`

关键点：

* `inner`：阈值→oneMask→填充成 innerMask
* `mem`：阈值→memMask→用 flood-fill 从边界找 bg→得到 innerMask（膜内水）
* `memBand`：由 subMask 生成固定厚度环带（用于 mem 强度）
* **近邻去重（旧逻辑保留）**：只对 `CType='mem'` 生效
  `Cfg.Detect.SuppressCloseOnMem=true` 时启用

### 6.3 Track：帧间关联（含全局漂移估计）

主函数：

* `functions/Track/guvTrack_trackCentroids.m`

思想（简述）：

* 预测：`PredPos = LastPos + dt * GlobalDrift`
* 代价：`pdist2(PredPos, CurrPos)`
* 关联：greedy 逐次选择最小代价并 gate
* 漂移：匹配对位移均值更新；不足时可相位相关备选

诊断输出：

* `XY###/TrackDiag/TrackDiag_FrameStats.csv`（nDet、nMatchPrev、meanIoU 等）

---

## 7. 输出说明

输出目录（只到 XY 层级）：

```
OutRoot/
  XY003/
    FramesMAT/Time_0001_Data.mat ...
    Debug/          % 逐帧 PNG + FuseLog
    DebugVideo/     % mp4（Ref底图 + Other底图）
    TrackDiag/      % 追踪诊断
    TTracks.mat
    XY003_Table.csv
OutRoot/AllXYResults.csv     % 计算后结果总表（替代旧 GUV_MASTER_DB.csv）
OutRoot/AllXYResults.mat
```

### 7.1 每帧 MAT：`GUVData`

常见字段：

* `centroids (N×2)`
* `majorAxisLength, Areas, filledAreas, Perimeters`
* `bboxes (N×4)`
* `subMasks {N×1}`（bbox ROI 内局部实心 mask）
* `memBandMasks {N×1}`（bbox ROI 内局部环带 mask）
* `meanIntensities_inner_C01 / _C02 ...`
* `meanIntensities_mem_C01 / _C02 ...`
* `meanIntensities_bg_C01 / _C02 ...`
* `imageSize`
* `I`：默认空（推荐），仅在 `Cfg.Output.SaveImgInFrameMAT=true` 时保存

### 7.2 轨迹 MAT：`TTracks`

* 结构体数组：每条轨迹包含 `frames` 与逐对象字段（从每帧 GUVData 自动搬运）

---

## 8. Debug（含 mem 可视化）怎么用？

### 8.1 逐帧 PNG（2×2 面板）

由 `functions/Debug/guvDebug_makeFrameFigureFuse.m` 生成：

* 左上：Ref 原图
* 右上：Other 原图
* 左下：Ref bbox/编号 + **主Ref subMask(绿) + memBand(红)**
* 右下：Other bbox/编号 + 同一套主Ref subMask/memBand

可选叠加该通道自身的 `memMask`（青色，容易显得乱，默认关）：

```matlab
Cfg.Debug.ShowMemMask = true;
```

### 8.2 Debug 视频两份

由 `functions/Series/guvSeries_makeDebugVideo.m` 输出：

* `XY003_Debug_refC01.mp4`
* `XY003_Debug_othC02.mp4`（`Cfg.Debug.SaveVideoBoth=true`）

---

## 9. 如何检查 mem 环带厚度是否合理？

最推荐断点位置（每个对象的 band 就在这里生成）：

* `functions/Detect/guvDetect_computeMemBandFromSubMasks.m`

断点停住后可临时叠加显示：

```matlab
imshow(mat2gray(I),[]); hold on;
visboundaries(subMask,'Color','g');
visboundaries(bandMask,'Color','r');
```

控制环带厚度的参数：

* `Cfg.Detect.Opts.band.width_px`（典型 2–5 px）

---

## 10. 追踪后分析方法（建议流程）

> 本包不内置“计算/过滤/可视化模块”，建议用导出的 MasterTable 做统一分析。

### 10.1 背景校正（每对象每帧）

对通道 `Cxx`：

* `I_inner_corr = meanIntensities_inner_Cxx - meanIntensities_bg_Cxx`
* `I_mem_corr   = meanIntensities_mem_Cxx   - meanIntensities_bg_Cxx`

### 10.2 常用指标

* 膜/内水比值：`R = I_mem_corr / (I_inner_corr + eps)`
* 双通道比值：`R_640_488 = I_inner_corr_C02 / (I_inner_corr_C01 + eps)`
* 按轨迹归一化：按第一帧或最大值归一（便于动力学比较）

### 10.3 质量过滤（推荐至少三条）

* 轨迹长度：`TrackLen >= Cfg.Track.MinLen`
* 尺寸过滤：`majorAxisLength_um = majorAxisLength_px * PixelSize_um`
* 强度过滤：背景校正后明显为负/异常大者剔除

### 10.4 MATLAB 小例：画单条轨迹的 inner/mem 曲线

```matlab
T = readtable(fullfile(Cfg.OutRoot,'AllXYResults.csv'));

sid = 3; tid = 10;
sub = T(T.SeriesID==sid & T.TrackID==tid, :);
sub = sortrows(sub, 'Frame');

C = 1;  % C01
inner = sub.(sprintf('meanIntensities_inner_C%02d',C));
mem   = sub.(sprintf('meanIntensities_mem_C%02d',C));
bg    = sub.(sprintf('meanIntensities_bg_C%02d',C));
innerCorr = inner - bg;
memCorr   = mem - bg;

tsec = (sub.Frame-1) * Cfg.FrameInterval_s;

figure; plot(tsec, innerCorr, '-o'); hold on;
plot(tsec, memCorr, '-o');
xlabel('Time (s)'); ylabel('Intensity (bg-corrected)');
legend('inner','mem'); grid on;
```

---

## 11. 常见问题（Troubleshooting）

1. **找不到 bfGetReader / bfGetPlaneAtZCT**

* 没把 `bfmatlab` 加进 path：`addpath(genpath(bfmatlabDir))`

2. **Debug 视频为空/没有写入帧**

* 底图读取失败。推荐保持：`Cfg.Output.SaveFrameStore=true`（默认）

3. **并行跑时 debug 输出爆炸**

* `Cfg.Debug.SingleXYOnly=true`（默认）
* 批量时建议关闭 `SaveFramePNG/SaveVideo`

4. **检测/追踪不稳**

* 先看 `Debug/Time_XXXX.png` 与 `TrackDiag` 判断是检测碎片化还是 gate 太严
* 适当调整：

  * 检测：`adapt_sensitivity / areaOpen / MinMajor_um / MaxMajor_um`
  * 追踪：`DistGate_um / MaxGap / EstimateGlobalDrift`

5. **汇总 AllXYResults.csv 时出现 readtable / readData 报错**

* 表现：`readtable` 报 `... determine whether "readData" is a function name`
* 常见原因：MATLAB 的 `readtable` 在某些 Linux 环境/路径组合下的内部异常，或 path 中存在同名符号/不可访问目录导致函数名解析异常
* 处理：

  * 直接使用 Pipeline 内置的 CSV 解析汇总（不依赖 `readtable`）：`guvCompute_collectAllXYResults(OutRoot, 'XY')`
  * 定位是否有 path 冲突：`which readData -all`、`which readtable -all`
  * 复现最小用例：`readtable(fullfile(OutRoot,'XY001','Computation','AllResults.csv'))`

---

## 12. 开发与协作建议

* 新增函数请按模块放入对应文件夹，并使用前缀命名（如 `guvDetect_xxx.m`）。
* 新增参数请集中写入 `guvPipeline_configDefault.m`，注明单位（um/px）与推荐范围。
* 不要把逻辑回塞成“一个巨型函数”，保持每步可断点、可单测。

---
