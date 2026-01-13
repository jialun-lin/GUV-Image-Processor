function opts = guvDetect_defaultOpts(opts, distanceThresh)
%GUVDETECT_DEFAULTOPTS 组装 detectGUVRegions 所需的 opts 默认值。
% 说明：
%   - 该函数把原 detectGUVRegions.m 中 localDefaultOpts + v3开关（detectMode/doSuppressClose/suppressCloseDist）
%     抽出来，便于单独断点调试。

if nargin < 1 || isempty(opts), opts = struct(); end
if nargin < 2, distanceThresh = []; end

% um/pixel (unknown -> 1 => pixel unit)
opts = guvUtil_setDefault(opts, 'pixel_size', 1);

% debug
if ~isfield(opts,'debug'), opts.debug = struct(); end
opts.debug = guvUtil_setDefault(opts.debug, 'makeFigure', true);

% binarization
if ~isfield(opts,'bin'), opts.bin = struct(); end
opts.bin = guvUtil_setDefault(opts.bin, 'sigma', 1);
opts.bin = guvUtil_setDefault(opts.bin, 'sensitivity', 0.3);
opts.bin = guvUtil_setDefault(opts.bin, 'invert', false);
opts.bin = guvUtil_setDefault(opts.bin, 'areaOpen', 50);
opts.bin = guvUtil_setDefault(opts.bin, 'closeR', 2);

% inner
if ~isfield(opts,'inner'), opts.inner = struct(); end
opts.inner = guvUtil_setDefault(opts.inner, 'seedRow', 2);
opts.inner = guvUtil_setDefault(opts.inner, 'nSeeds', 10);
opts.inner = guvUtil_setDefault(opts.inner, 'areaOpen', 30);

% split (watershed)
if ~isfield(opts,'split'), opts.split = struct(); end
opts.split = guvUtil_setDefault(opts.split, 'doSplit', true);
opts.split = guvUtil_setDefault(opts.split, 'splitH', 1.0);
opts.split = guvUtil_setDefault(opts.split, 'openR', 2);

% geometry (axisymmetric)
if ~isfield(opts,'geom'), opts.geom = struct(); end
opts.geom = guvUtil_setDefault(opts.geom, 'enable', true);
opts.geom = guvUtil_setDefault(opts.geom, 'nSamples', 400);
opts.geom = guvUtil_setDefault(opts.geom, 'spline_p', 0.999);
opts.geom = guvUtil_setDefault(opts.geom, 'smooth_window', 9);
opts.geom = guvUtil_setDefault(opts.geom, 'poleZFrac', 0.02);
opts.geom = guvUtil_setDefault(opts.geom, 'eps_r', 1e-6);

% ===== v3: 检测模式/去重开关 =====
opts = guvUtil_setDefault(opts, 'detectMode', 'merge');
opts = guvUtil_setDefault(opts, 'doSuppressClose', true);
if ~isfield(opts,'suppressCloseDist') || isempty(opts.suppressCloseDist)
    if ~isempty(distanceThresh)
        opts.suppressCloseDist = distanceThresh;
    else
        opts.suppressCloseDist = 0;
    end
end

% ===== 膜band参数（从 subMask 派生） =====
if ~isfield(opts,'mem'), opts.mem = struct(); end
opts.mem = guvUtil_setDefault(opts.mem, 'smoothR', 2);
opts.mem = guvUtil_setDefault(opts.mem, 'thickR', 3);

end
