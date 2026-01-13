function [I_norm, bw, I_smooth] = guvDetect_binarizeAdaptive(I, binOpt)
%GUVDETECT_BINARIZEADAPTIVE 自适应阈值 + 形态学清理，输出膜候选 bw(1=mem)。
% 与 detectGUVRegions 保持一致：
%   1) mat2gray 归一化
%   2) 高斯平滑
%   3) imbinarize('adaptive') + 可选 invert
%   4) bwareaopen + imclose

if nargin < 2, binOpt = struct(); end

% ---- backward compatibility for config keys ----
% Older config/template used `adapt_sensitivity`; canonical key is `sensitivity`.
if isfield(binOpt,'adapt_sensitivity') && ~isfield(binOpt,'sensitivity')
    binOpt.sensitivity = binOpt.adapt_sensitivity;
end
binOpt = guvUtil_setDefault(binOpt,'sigma',1);
binOpt = guvUtil_setDefault(binOpt,'sensitivity',0.3);
binOpt = guvUtil_setDefault(binOpt,'invert',false);
binOpt = guvUtil_setDefault(binOpt,'areaOpen',50);
binOpt = guvUtil_setDefault(binOpt,'closeR',2);

binOpt = guvUtil_setDefault(binOpt,'minHoleArea',0);

I_norm = mat2gray(I);
I_smooth = imgaussfilt(I_norm, binOpt.sigma);

bw = imbinarize(I_smooth, 'adaptive', 'Sensitivity', binOpt.sensitivity);
if binOpt.invert
    bw = ~bw;
end


% Optional: fill *small* holes inside foreground regions.
% minHoleArea is in px^2; holes smaller than this will be filled.
if isfield(binOpt,'minHoleArea') && ~isempty(binOpt.minHoleArea) && binOpt.minHoleArea > 0
    minA = max(1, round(binOpt.minHoleArea));
    bw_filled = imfill(bw, 'holes');
    holes = bw_filled & ~bw;
    if any(holes(:))
        holes_big = bwareaopen(holes, minA);  % keep holes >= minA
        holes_small = holes & ~holes_big;     % holes < minA
        bw = bw | holes_small;                % fill small holes
    end
end

bw = bwareaopen(bw, binOpt.areaOpen);
bw = imclose(bw, strel('disk', binOpt.closeR));
end
