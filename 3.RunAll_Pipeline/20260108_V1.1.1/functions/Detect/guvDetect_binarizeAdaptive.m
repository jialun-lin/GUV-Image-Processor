function [I_norm, bw, I_smooth] = guvDetect_binarizeAdaptive(I, binOpt)
%GUVDETECT_BINARIZEADAPTIVE 自适应阈值 + 形态学清理，输出膜候选 bw(1=mem)。
% 与 detectGUVRegions 保持一致：
%   1) mat2gray 归一化
%   2) 高斯平滑
%   3) imbinarize('adaptive') + 可选 invert
%   4) bwareaopen + imclose

if nargin < 2, binOpt = struct(); end
binOpt = guvUtil_setDefault(binOpt,'sigma',1);
binOpt = guvUtil_setDefault(binOpt,'sensitivity',0.3);
binOpt = guvUtil_setDefault(binOpt,'invert',false);
binOpt = guvUtil_setDefault(binOpt,'areaOpen',50);
binOpt = guvUtil_setDefault(binOpt,'closeR',2);

I_norm = mat2gray(I);
I_smooth = imgaussfilt(I_norm, binOpt.sigma);

bw = imbinarize(I_smooth, 'adaptive', 'Sensitivity', binOpt.sensitivity);
if binOpt.invert
    bw = ~bw;
end

bw = bwareaopen(bw, binOpt.areaOpen);
bw = imclose(bw, strel('disk', binOpt.closeR));
end
